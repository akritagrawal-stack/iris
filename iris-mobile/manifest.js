/**
 * Pure catalog manifest validation and bounded metadata loading for the mobile hub.
 * The module deliberately does not know about a framework, native installer, or
 * binary payloads.
 */

export const MAX_MANIFEST_BYTES = 64 * 1024;
export const MAX_APPS = 32;
export const MAX_TEXT_LENGTH = 240;
export const MAX_TITLE_LENGTH = 80;
export const MAX_URL_LENGTH = 2_048;
export const CACHE_KEY = "iris-mobile.catalog.v1";
export const CACHE_MAX_BYTES = 64 * 1024;
export const CACHE_MAX_AGE_MS = 24 * 60 * 60 * 1_000;

export const DEVICES = Object.freeze(["iphone", "android", "computer"]);
export const ROUTE_KINDS = Object.freeze([
  "web",
  "app-store",
  "testflight",
  "android-package",
  "mac-assisted",
  "unavailable",
]);

const ROUTE_HOSTS = Object.freeze({
  web: new Set(["publikhq.com", "www.publikhq.com"]),
  "app-store": new Set(["apps.apple.com"]),
  testflight: new Set(["testflight.apple.com"]),
  "android-package": new Set(["play.google.com"]),
  "mac-assisted": new Set(["publikhq.com", "www.publikhq.com", "github.com"]),
});
const SENSITIVE_QUERY_KEYS = new Set(["token", "access_token", "api_key", "apikey", "secret", "password", "credential", "auth", "signature", "sig"]);

const DEVICE_ROUTE_KINDS = Object.freeze({
  iphone: new Set(["web", "app-store", "testflight", "unavailable"]),
  android: new Set(["web", "android-package", "unavailable"]),
  computer: new Set(["web", "mac-assisted", "unavailable"]),
});

export class ManifestError extends Error {
  constructor(message, code = "invalid-manifest") {
    super(message);
    this.name = "ManifestError";
    this.code = code;
  }
}

function fail(message, code) {
  throw new ManifestError(message, code);
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function assertRecord(value, label) {
  if (!isRecord(value)) fail(`${label} must be an object`);
}

function assertKeys(value, allowed, label) {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) fail(`${label} contains unsupported field: ${key}`);
  }
}

function assertText(value, label, max = MAX_TEXT_LENGTH) {
  if (typeof value !== "string" || value.trim().length === 0) fail(`${label} must be non-empty text`);
  if (value.length > max) fail(`${label} exceeds ${max} characters`, "text-too-long");
  if ([...value].some((character) => character.charCodeAt(0) < 32 && character !== "\n" && character !== "\t")) {
    fail(`${label} contains a control character`);
  }
}

function assertUrl(value, label, allowedHosts) {
  if (typeof value !== "string" || value.length === 0) fail(`${label} must be an HTTPS URL`);
  if (value.length > MAX_URL_LENGTH) fail(`${label} exceeds ${MAX_URL_LENGTH} characters`, "url-too-long");
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    fail(`${label} is not a valid URL`, "invalid-url");
  }
  if (parsed.protocol !== "https:") fail(`${label} must use HTTPS`, "unsafe-url");
  if (parsed.username || parsed.password) fail(`${label} must not contain credentials`, "unsafe-url");
  if (parsed.port && parsed.port !== "443") fail(`${label} must use the standard HTTPS port`, "unsafe-url");
  const host = parsed.hostname.toLowerCase();
  if (!allowedHosts.has(host)) fail(`${label} host is not verified`, "unverified-host");
  for (const key of parsed.searchParams.keys()) {
    if (SENSITIVE_QUERY_KEYS.has(key.toLowerCase())) fail(`${label} contains a credential-like query parameter`, "unsafe-url");
  }
  return parsed.href;
}

function validateIcon(icon) {
  if (!isRecord(icon)) fail("app.icon must be an object");
  assertKeys(icon, new Set(["kind", "label", "url"]), "app.icon");
  if (icon.kind === "fallback") {
    assertText(icon.label, "app.icon.label", 4);
    return { kind: "fallback", label: icon.label.trim() };
  }
  if (icon.kind === "url") {
    return { kind: "url", url: assertUrl(icon.url, "app.icon.url", new Set(["publikhq.com", "www.publikhq.com"])) };
  }
  fail("app.icon.kind must be fallback or url");
}

function validatePrerequisites(value, label) {
  if (!Array.isArray(value) || value.length > 6) fail(`${label} must be an array of up to 6 actions`);
  return value.map((action, index) => {
    assertText(action, `${label}[${index}]`);
    return action.trim();
  });
}

function validateRoute(route, device) {
  assertRecord(route, `routes.${device}`);
  assertKeys(route, new Set(["kind", "destination", "status", "evidence", "nextActions"]), `routes.${device}`);
  if (!ROUTE_KINDS.includes(route.kind)) fail(`routes.${device}.kind is unsupported`, "unsupported-route");
  if (!DEVICE_ROUTE_KINDS[device].has(route.kind)) fail(`routes.${device}.kind is incompatible with ${device}`, "incompatible-route");
  if (route.status !== "verified" && route.status !== "unavailable") fail(`routes.${device}.status must be verified or unavailable`);
  if (route.evidence !== undefined) assertText(route.evidence, `routes.${device}.evidence`);
  const nextActions = route.nextActions === undefined ? [] : validatePrerequisites(route.nextActions, `routes.${device}.nextActions`);
  const destination = route.destination === null || route.destination === undefined
    ? null
    : assertUrl(route.destination, `routes.${device}.destination`, ROUTE_HOSTS[route.kind] || new Set());
  if (route.kind === "unavailable" || route.status === "unavailable") {
    if (destination !== null) fail(`routes.${device} cannot expose a destination while unavailable`, "unavailable-destination");
  } else {
    if (destination === null) fail(`routes.${device} needs a verified HTTPS destination`, "missing-destination");
    if (route.status !== "verified") fail(`routes.${device} must be verified when a destination exists`);
  }
  return { kind: route.kind, destination, status: route.status, evidence: route.evidence?.trim() || "", nextActions };
}

function validateSource(source, appId) {
  assertRecord(source, "app.source");
  assertKeys(source, new Set(["guideSlug", "revision", "repository"]), "app.source");
  assertText(source.guideSlug, "app.source.guideSlug", 80);
  if (!/^[a-z0-9]+(?:[-_][a-z0-9]+)*$/.test(source.guideSlug.trim())) fail("app.source.guideSlug is invalid");
  if (typeof source.revision !== "string" || !/^[0-9a-f]{40}$/i.test(source.revision)) fail("app.source.revision must be a 40-character commit pin");
  return {
    guideSlug: source.guideSlug.trim(),
    revision: source.revision.toLowerCase(),
    repository: assertUrl(source.repository, "app.source.repository", new Set(["github.com"])),
  };
}

function validateApp(app) {
  assertRecord(app, "manifest.apps[]");
  assertKeys(app, new Set(["id", "title", "icon", "os", "routes", "source", "capabilities", "setup", "setupGuide"]), "manifest.apps[]");
  if (typeof app.id !== "string" || !/^[a-z0-9]+(?:[-_][a-z0-9]+)*$/.test(app.id) || app.id.length > 80) fail("app.id is invalid");
  assertText(app.title, "app.title", MAX_TITLE_LENGTH);
  const os = Array.isArray(app.os) ? [...new Set(app.os)] : fail("app.os must be a non-empty array");
  if (os.length === 0 || os.some((device) => !DEVICES.includes(device))) fail("app.os contains an unsupported device", "unsupported-os");
  const icon = validateIcon(app.icon);
  assertRecord(app.routes, "app.routes");
  assertKeys(app.routes, new Set(DEVICES), "app.routes");
  const routes = Object.fromEntries(DEVICES.map((device) => [device, validateRoute(app.routes[device], device)]));
  for (const device of DEVICES) {
    if (routes[device].status === "verified" && !os.includes(device)) fail(`verified ${device} route requires that device in app.os`, "incompatible-os");
  }
  if (isRecord(app.setup)) {
    assertKeys(app.setup, new Set(DEVICES), "app.setup");
  } else if (app.setup !== undefined) {
    fail("app.setup must be an object");
  }
  const setup = Object.fromEntries(DEVICES.map((device) => [device, app.setup?.[device] === undefined ? [] : validatePrerequisites(app.setup[device], `app.setup.${device}`)]));
  const capabilities = app.capabilities === undefined ? [] : validatePrerequisites(app.capabilities, "app.capabilities");
  let setupGuide = null;
  if (app.setupGuide !== undefined) {
    assertRecord(app.setupGuide, "app.setupGuide");
    assertKeys(app.setupGuide, new Set(["destination", "label"]), "app.setupGuide");
    assertText(app.setupGuide.label, "app.setupGuide.label", MAX_TITLE_LENGTH);
    setupGuide = { label: app.setupGuide.label.trim(), destination: assertUrl(app.setupGuide.destination, "app.setupGuide.destination", new Set(["publikhq.com", "www.publikhq.com"])) };
  }
  return {
    id: app.id,
    title: app.title.trim(),
    icon,
    os,
    routes,
    source: validateSource(app.source, app.id),
    capabilities,
    setup,
    setupGuide,
  };
}

export function parseManifestText(text) {
  if (typeof text !== "string") fail("manifest response must be text", "invalid-manifest");
  const bytes = new TextEncoder().encode(text).byteLength;
  if (bytes > MAX_MANIFEST_BYTES) fail(`manifest exceeds ${MAX_MANIFEST_BYTES} bytes`, "manifest-too-large");
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    fail("manifest is not valid JSON", "invalid-manifest");
  }
  return validateManifest(value, bytes);
}

export function validateManifest(manifest, knownBytes) {
  assertRecord(manifest, "manifest");
  assertKeys(manifest, new Set(["schemaVersion", "apps", "prototype", "label"]), "manifest");
  if (manifest.schemaVersion !== 1) fail("manifest.schemaVersion must be 1", "unsupported-schema");
  if (!Array.isArray(manifest.apps) || manifest.apps.length > MAX_APPS) fail(`manifest.apps must contain at most ${MAX_APPS} apps`, "app-limit");
  if (manifest.prototype !== true) fail("manifest must be explicitly labeled as a local prototype");
  assertText(manifest.label, "manifest.label", MAX_TEXT_LENGTH);
  if (knownBytes === undefined) {
    const bytes = new TextEncoder().encode(JSON.stringify(manifest)).byteLength;
    if (bytes > MAX_MANIFEST_BYTES) fail(`manifest exceeds ${MAX_MANIFEST_BYTES} bytes`, "manifest-too-large");
  }
  const seen = new Set();
  const apps = manifest.apps.map((app) => {
    if (seen.has(app?.id)) fail(`duplicate app id: ${app?.id || "unknown"}`, "duplicate-id");
    const normalized = validateApp(app);
    if (seen.has(normalized.id)) fail(`duplicate app id: ${normalized.id}`, "duplicate-id");
    seen.add(normalized.id);
    return normalized;
  });
  return { schemaVersion: 1, prototype: true, label: manifest.label.trim(), apps };
}

export function createMemoryCache() {
  let entry = null;
  return {
    read() { return entry; },
    write(value) {
      const serialized = JSON.stringify(value);
      if (new TextEncoder().encode(serialized).byteLength > CACHE_MAX_BYTES) return false;
      entry = value;
      return true;
    },
  };
}

export function createStorageCache(storage, key = CACHE_KEY) {
  return {
    read() {
      try {
        const raw = storage.getItem(key);
        if (!raw) return null;
        const entry = JSON.parse(raw);
        if (!isRecord(entry) || typeof entry.savedAt !== "number" || typeof entry.manifestText !== "string") return null;
        if (new TextEncoder().encode(raw).byteLength > CACHE_MAX_BYTES) return null;
        return entry;
      } catch {
        return null;
      }
    },
    write(entry) {
      try {
        const raw = JSON.stringify(entry);
        if (new TextEncoder().encode(raw).byteLength > CACHE_MAX_BYTES) return false;
        storage.setItem(key, raw);
        return true;
      } catch {
        return false;
      }
    },
  };
}

export function createCatalogClient({ fetchImpl = globalThis.fetch, cache = createMemoryCache(), now = () => Date.now(), maxAgeMs = CACHE_MAX_AGE_MS } = {}) {
  if (typeof fetchImpl !== "function") throw new TypeError("fetchImpl is required");
  let inFlight = null;
  let requestCount = 0;

  function cachedResult({ allowStale = false } = {}) {
    const entry = cache.read();
    if (!entry || typeof entry.manifestText !== "string" || typeof entry.savedAt !== "number") return null;
    if (!allowStale && now() - entry.savedAt > maxAgeMs) return null;
    try {
      return { manifest: parseManifestText(entry.manifestText), source: "cache", savedAt: entry.savedAt };
    } catch {
      return null;
    }
  }

  async function readBoundedText(response) {
    if (response.body && typeof response.body.getReader === "function") {
      const reader = response.body.getReader();
      const chunks = [];
      let size = 0;
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          if (!(value instanceof Uint8Array)) fail("catalog response contains invalid bytes", "invalid-manifest");
          size += value.byteLength;
          if (size > MAX_MANIFEST_BYTES) fail(`manifest exceeds ${MAX_MANIFEST_BYTES} bytes`, "manifest-too-large");
          chunks.push(value);
        }
      } finally {
        reader.releaseLock?.();
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      return new TextDecoder().decode(bytes);
    }
    if (typeof response.text !== "function") fail("catalog response has no readable body", "network-error");
    const text = await response.text();
    if (new TextEncoder().encode(text).byteLength > MAX_MANIFEST_BYTES) fail(`manifest exceeds ${MAX_MANIFEST_BYTES} bytes`, "manifest-too-large");
    return text;
  }

  async function load({ force = false, offline = false } = {}) {
    if (inFlight) return inFlight;
    const cached = cachedResult();
    const staleCached = cached || cachedResult({ allowStale: true });
    if (offline) {
      if (staleCached) return cached ? cached : { ...staleCached, stale: true };
      throw new ManifestError("Offline and no verified catalog is cached", "offline-no-cache");
    }
    if (!force && cached) return cached;
    inFlight = (async () => {
      requestCount += 1;
      try {
        const response = await fetchImpl("./prototype-manifest.json", { cache: "no-store", headers: { Accept: "application/json" } });
        if (!response || !response.ok) throw new ManifestError(`Catalog request failed (${response?.status || "network"})`, "network-error");
        const text = await readBoundedText(response);
        const manifest = parseManifestText(text);
        const savedAt = now();
        cache.write({ savedAt, manifestText: text });
        return { manifest, source: "network", savedAt };
      } catch (error) {
        if (staleCached) return { ...staleCached, stale: true, error };
        throw error;
      } finally {
        inFlight = null;
      }
    })();
    return inFlight;
  }

  return {
    load,
    refresh(options = {}) { return load({ ...options, force: true }); },
    get requestCount() { return requestCount; },
    cachedResult,
  };
}
