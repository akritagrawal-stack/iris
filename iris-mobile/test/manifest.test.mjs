import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  MAX_APPS,
  MAX_MANIFEST_BYTES,
  ManifestError,
  createCatalogClient,
  createDevicePreferenceStore,
  createMemoryCache,
  mapCatalogResponse,
  parseCatalogText,
  parseManifestText,
  validateManifest,
} from "../manifest.js";
import { createCatalogProxy } from "../catalog-proxy.mjs";

const revision = "fc48ba487a1e0d0cd10b30d6600acd2895ffdbed";

function validManifest(overrides = {}) {
  return {
    schemaVersion: 1,
    prototype: true,
    label: "Local prototype",
    observedAt: "2026-09-12T23:00:00.000Z",
    apps: [{
      id: "kneecap",
      title: "Kneecap",
      icon: { kind: "fallback", label: "K" },
      os: ["iphone", "android"],
      routes: {
        iphone: { kind: "unavailable", destination: null, status: "unavailable", nextActions: ["Publish a signed TestFlight build."] },
        android: { kind: "unavailable", destination: null, status: "unavailable", nextActions: ["Publish a signed package."] },
        computer: { kind: "unavailable", destination: null, status: "unavailable", nextActions: ["Publish a computer route."] },
      },
      source: { guideSlug: "kneecap", revision, repository: "https://github.com/Blueturboguy07/kneecap" },
      ...overrides,
    }],
  };
}

test("persists only a supported device choice and ignores bad storage", () => {
  const values = new Map();
  const storage = {
    getItem(key) { return values.get(key) ?? null; },
    setItem(key, value) { values.set(key, value); },
  };
  const preferences = createDevicePreferenceStore(storage);
  assert.equal(preferences.read(), null);
  assert.equal(preferences.write("iphone"), true);
  assert.equal(preferences.read(), "iphone");
  assert.equal(preferences.write("phone"), false);
  values.set("iris-mobile.device.v1", "phone");
  assert.equal(preferences.read(), null);

  const brokenStorage = {
    getItem() { throw new Error("storage unavailable"); },
    setItem() { throw new Error("storage unavailable"); },
  };
  const broken = createDevicePreferenceStore(brokenStorage);
  assert.equal(broken.read(), null);
  assert.equal(broken.write("android"), false);
  assert.equal(createDevicePreferenceStore(undefined).write("iphone"), false);
});

function rawCatalog(overrides = {}) {
  return {
    apps: [{ slug: "kneecap", name: "kneecap", macBundleId: null, latestReleaseTag: null, guideSlug: "kneecap", ...overrides }],
  };
}

function expectManifestError(action, code) {
  assert.throws(action, (error) => error instanceof ManifestError && (!code || error.code === code));
}

test("maps the opt-in fixture through the same adapter as production", async () => {
  const text = await (await import("node:fs/promises")).readFile(new URL("../prototype-manifest.json", import.meta.url), "utf8");
  const manifest = parseCatalogText(text, { prototype: true, observedAt: "2026-09-12T23:00:00.000Z" });
  assert.equal(manifest.prototype, true);
  assert.equal(manifest.apps[0].id, "kneecap");
  assert.equal(manifest.apps[0].source.revision, null);
  assert.equal(manifest.apps[0].routes.iphone.destination, null);
  assert.equal(manifest.apps[0].icon.kind, "fallback");
});

test("maps observed live fields without inventing native routes or a commit pin", () => {
  const manifest = mapCatalogResponse({ apps: [{ slug: "cue", name: "cue", macBundleId: "com.cue.overlay", latestReleaseTag: "v0.2.2", guideSlug: "cue" }] }, { observedAt: "2026-09-12T23:00:00.000Z" });
  const app = manifest.apps[0];
  assert.deepEqual(app.os, []);
  assert.equal(app.source.guideSlug, "cue");
  assert.equal(app.source.releaseTag, "v0.2.2");
  assert.equal(app.source.revision, null);
  assert.equal(app.source.repository, null);
  assert.equal(app.routes.computer.status, "unavailable");
  assert.equal(app.routes.computer.destination, null);
  assert.equal(app.icon.kind, "fallback");
});

test("maps a checked-in sample of the actual catalog response", async () => {
  const text = await readFile(new URL("./fixtures/live-catalog.json", import.meta.url), "utf8");
  const manifest = parseCatalogText(text, { observedAt: "2026-09-12T23:24:09.000Z" });
  assert.equal(manifest.apps.length, 2);
  assert.equal(manifest.apps[0].observations.macBundleId, "com.cue.overlay");
  assert.equal(manifest.apps[1].source.revision, null);
  assert.equal(manifest.apps[1].routes.iphone.status, "unavailable");
});

test("keeps missing platform, link, and pin fields unknown", async () => {
  const text = await readFile(new URL("./fixtures/missing-fields.json", import.meta.url), "utf8");
  const manifest = parseCatalogText(text, { observedAt: "2026-09-12T23:00:00.000Z" });
  const app = manifest.apps[0];
  assert.deepEqual(app.os, []);
  assert.equal(app.source.guideSlug, null);
  assert.equal(app.source.revision, null);
  assert.equal(app.setupGuide, null);
  for (const device of ["iphone", "android", "computer"]) assert.equal(app.routes[device].destination, null);
});

test("preserves a valid observed icon URL and rejects an unsafe one", () => {
  const mapped = mapCatalogResponse({ apps: [{ slug: "icon-app", name: "Icon App", macBundleId: null, latestReleaseTag: null, guideSlug: "icon-app", iconUrl: "https://publikhq.com/assets/icon.png" }] }, { observedAt: "2026-09-12T23:00:00.000Z" });
  assert.deepEqual(mapped.apps[0].icon, { kind: "url", url: "https://publikhq.com/assets/icon.png" });
  expectManifestError(() => mapCatalogResponse({ apps: [{ slug: "icon-app", name: "Icon App", macBundleId: null, latestReleaseTag: null, guideSlug: "icon-app", iconUrl: "https://evil.example/icon.png" }] }, { observedAt: "2026-09-12T23:00:00.000Z" }), "unverified-host");
});

test("rejects malformed, oversized, and duplicate manifests", () => {
  expectManifestError(() => parseManifestText("{"));
  expectManifestError(() => validateManifest({}));
  expectManifestError(() => parseManifestText("x".repeat(MAX_MANIFEST_BYTES + 1)), "manifest-too-large");
  const duplicate = validManifest();
  duplicate.apps.push({ ...duplicate.apps[0] });
  expectManifestError(() => validateManifest(duplicate), "duplicate-id");
  const tooMany = validManifest();
  tooMany.apps = Array.from({ length: MAX_APPS + 1 }, (_, index) => ({ ...tooMany.apps[0], id: `app-${index}` }));
  expectManifestError(() => validateManifest(tooMany), "app-limit");
});

test("rejects unsafe URLs, host violations, and forged native routes", () => {
  const credentials = validManifest();
  credentials.apps[0].routes.iphone = { kind: "testflight", destination: "https://u:p@testflight.apple.com/join/x", status: "verified" };
  expectManifestError(() => validateManifest(credentials), "unsafe-url");
  const wrongHost = validManifest();
  wrongHost.apps[0].routes.iphone = { kind: "testflight", destination: "https://evil.example/join/x", status: "verified" };
  expectManifestError(() => validateManifest(wrongHost), "unverified-host");
  const http = validManifest();
  http.apps[0].routes.iphone = { kind: "app-store", destination: "http://apps.apple.com/app/x", status: "verified" };
  expectManifestError(() => validateManifest(http), "unsafe-url");
  const incompatible = validManifest();
  incompatible.apps[0].routes.android = { kind: "testflight", destination: "https://testflight.apple.com/join/x", status: "verified" };
  expectManifestError(() => validateManifest(incompatible), "incompatible-route");
  const missing = validManifest();
  missing.apps[0].routes.iphone = { kind: "testflight", destination: null, status: "verified" };
  expectManifestError(() => validateManifest(missing), "missing-destination");
  const querySecret = validManifest();
  querySecret.apps[0].routes.iphone = { kind: "testflight", destination: "https://testflight.apple.com/join/x?access_token=leak", status: "verified" };
  expectManifestError(() => validateManifest(querySecret), "unsafe-url");
});

test("allows only verified destinations to become actionable routes", () => {
  const manifest = validManifest();
  manifest.apps[0].routes.iphone = { kind: "testflight", destination: "https://testflight.apple.com/join/real", status: "verified" };
  const normalized = validateManifest(manifest);
  assert.equal(normalized.apps[0].routes.iphone.destination, "https://testflight.apple.com/join/real");
  const unavailable = validManifest();
  unavailable.apps[0].routes.iphone.kind = "testflight";
  unavailable.apps[0].routes.iphone.destination = "https://testflight.apple.com/join/real";
  expectManifestError(() => validateManifest(unavailable), "unavailable-destination");
  const excluded = validManifest();
  excluded.apps[0].os = ["android"];
  excluded.apps[0].routes.iphone = { kind: "testflight", destination: "https://testflight.apple.com/join/real", status: "verified" };
  expectManifestError(() => validateManifest(excluded), "incompatible-os");
  const differentSlug = validManifest();
  differentSlug.apps[0].source.guideSlug = "kneecap-beta";
  assert.equal(validateManifest(differentSlug).apps[0].source.guideSlug, "kneecap-beta");
});

test("coalesces concurrent refreshes to one request", async () => {
  const cache = createMemoryCache();
  const text = JSON.stringify(rawCatalog());
  let calls = 0;
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const client = createCatalogClient({
    cache,
    fetchImpl: async () => {
      calls += 1;
      await gate;
      return { ok: true, status: 200, text: async () => text };
    },
  });
  const first = client.refresh();
  const second = client.refresh();
  assert.equal(client.requestCount, 1);
  release();
  const [a, b] = await Promise.all([first, second]);
  assert.equal(calls, 1);
  assert.equal(a.manifest.apps[0].id, b.manifest.apps[0].id);
});

test("uses verified cached metadata offline and reports no-cache offline", async () => {
  const text = JSON.stringify(rawCatalog());
  const cache = createMemoryCache();
  let now = 10_000;
  const client = createCatalogClient({ cache, now: () => now, fetchImpl: async () => ({ ok: true, text: async () => text }) });
  await client.refresh();
  const cached = await client.load({ offline: true });
  assert.equal(cached.source, "cache");
  assert.equal(cached.offline, true);
  assert.equal(cached.stale, undefined);
  now += 25 * 60 * 60 * 1_000;
  const stale = await client.load({ offline: true });
  assert.equal(stale.stale, true);
  assert.equal(stale.offline, true);
  const emptyClient = createCatalogClient({ cache: createMemoryCache(), now: () => now, fetchImpl: async () => ({ ok: true, text: async () => text }) });
  await assert.rejects(() => emptyClient.load({ offline: true }), (error) => error.code === "offline-no-cache");
});

test("falls back to stale verified metadata after a network failure", async () => {
  const text = JSON.stringify(rawCatalog());
  const cache = createMemoryCache();
  let now = 10_000;
  let fail = false;
  const client = createCatalogClient({ cache, now: () => now, fetchImpl: async () => {
    if (fail) throw new Error("offline");
    return { ok: true, text: async () => text };
  } });
  await client.refresh();
  now += 25 * 60 * 60 * 1_000;
  fail = true;
  const result = await client.refresh();
  assert.equal(result.stale, true);
  assert.equal(result.manifest.apps[0].id, "kneecap");
});

test("caps a streamed response while it is being read", async () => {
  const cache = createMemoryCache();
  const oversized = new Uint8Array(MAX_MANIFEST_BYTES + 1);
  let cancelled = false;
  const client = createCatalogClient({ cache, fetchImpl: async () => ({
    ok: true,
    body: {
      getReader() {
        let sent = false;
        return {
          async read() {
            if (sent) return { done: true };
            sent = true;
            return { done: false, value: oversized };
          },
          cancel() { cancelled = true; },
          releaseLock() {},
        };
      },
    },
  }) });
  await assert.rejects(() => client.refresh(), (error) => error.code === "manifest-too-large");
  assert.equal(cancelled, true);
});

test("times out a stalled fetch, falls back to cache, clears inFlight, and recovers", async () => {
  const cache = createMemoryCache();
  const text = JSON.stringify(rawCatalog());
  let mode = "seed";
  let signal;
  let now = 10_000;
  const client = createCatalogClient({ cache, now: () => now, timeoutMs: 5, fetchImpl: async (_url, options) => {
    signal = options.signal;
    if (mode === "stall") return new Promise((_resolve, reject) => options.signal.addEventListener("abort", () => reject(options.signal.reason), { once: true }));
    return { ok: true, text: async () => text };
  } });
  await client.refresh();
  now += 25 * 60 * 60 * 1_000;
  mode = "stall";
  const stale = await client.refresh();
  assert.equal(stale.stale, true);
  assert.equal(stale.error.code, "network-timeout");
  assert.equal(signal.aborted, true);
  assert.equal(client.requestCount, 2);
  mode = "recover";
  const recovered = await client.refresh();
  assert.equal(recovered.stale, undefined);
  assert.equal(client.requestCount, 3);
});

test("times out a stalled body read, cancels the reader, and recovers", async () => {
  const cache = createMemoryCache();
  const text = JSON.stringify(rawCatalog());
  let mode = "seed";
  let cancelled = false;
  let now = 10_000;
  const client = createCatalogClient({ cache, now: () => now, timeoutMs: 5, fetchImpl: async () => {
    if (mode === "stall-body") return {
      ok: true,
      body: {
        getReader() {
          return {
            read: () => new Promise(() => {}),
            cancel() { cancelled = true; },
            releaseLock() {},
          };
        },
      },
    };
    return { ok: true, text: async () => text };
  } });
  await client.refresh();
  now += 25 * 60 * 60 * 1_000;
  mode = "stall-body";
  const stale = await client.refresh();
  assert.equal(stale.stale, true);
  assert.equal(stale.error.code, "network-timeout");
  assert.equal(cancelled, true);
  mode = "recover";
  const recovered = await client.refresh();
  assert.equal(recovered.stale, undefined);
});

test("proxy cancels oversized upstream bodies and never caches malformed responses", async () => {
  const text = JSON.stringify(rawCatalog());
  let mode = "oversize";
  let cancelled = false;
  let now = 10_000;
  const proxy = createCatalogProxy({ now: () => now, fetchImpl: async () => {
    if (mode === "oversize") return {
      ok: true,
      body: {
        getReader() {
          return {
            read: async () => ({ done: false, value: new Uint8Array(MAX_MANIFEST_BYTES + 1) }),
            cancel() { cancelled = true; },
            releaseLock() {},
          };
        },
      },
    };
    if (mode === "malformed") return { ok: true, text: async () => "{}" };
    return { ok: true, text: async () => text };
  } });
  await assert.rejects(() => proxy.fetchCatalog());
  assert.equal(cancelled, true);
  mode = "malformed";
  await assert.rejects(() => proxy.fetchCatalog());
  now += 6 * 60 * 1_000;
  mode = "valid";
  const recovered = await proxy.fetchCatalog();
  assert.equal(JSON.parse(recovered.text).apps[0].slug, "kneecap");
  assert.equal(proxy.requestCount, 3);
});

test("rejects unsafe or forged route URLs even when the source mapper is valid", () => {
  const base = validManifest({});
  for (const [destination, code] of [
    ["https://u:p@testflight.apple.com/join/x", "unsafe-url"],
    ["https://evil.example/join/x", "unverified-host"],
    ["http://apps.apple.com/app/x", "unsafe-url"],
  ]) {
    const forged = structuredClone(base);
    forged.apps[0].routes.iphone = { kind: destination.includes("testflight") ? "testflight" : "app-store", destination, status: "verified" };
    expectManifestError(() => validateManifest(forged), code);
  }
});

test("rejects malformed live catalog records and duplicate IDs", () => {
  expectManifestError(() => parseCatalogText("{"));
  expectManifestError(() => mapCatalogResponse({ apps: [{ slug: "bad slug", name: "Bad", macBundleId: null, latestReleaseTag: null, guideSlug: null }] }, { observedAt: "2026-09-12T23:00:00.000Z" }));
  expectManifestError(() => mapCatalogResponse({ apps: [
    { slug: "same", name: "Same", macBundleId: null, latestReleaseTag: null, guideSlug: null },
    { slug: "same", name: "Same again", macBundleId: null, latestReleaseTag: null, guideSlug: null },
  ] }, { observedAt: "2026-09-12T23:00:00.000Z" }), "duplicate-id");
});

test("bounds an oversized catalog without silently hiding the omitted count", () => {
  const apps = Array.from({ length: MAX_APPS + 1 }, (_, index) => ({
    slug: `app-${index}`,
    name: `App ${index}`,
    macBundleId: null,
    latestReleaseTag: null,
    guideSlug: `app-${index}`,
    routes: { iphone: { kind: "testflight", destination: "https://evil.example/forged", status: "verified" } },
    platform: "iphone",
  }));
  const manifest = mapCatalogResponse({ apps }, { observedAt: "2026-09-12T23:00:00.000Z" });
  assert.equal(manifest.apps.length, MAX_APPS);
  assert.equal(manifest.totalApps, MAX_APPS + 1);
  assert.equal(manifest.truncated, true);
  assert.equal(manifest.apps.at(-1).id, "app-31");
  assert.equal(manifest.apps[0].routes.iphone.destination, null);
});
