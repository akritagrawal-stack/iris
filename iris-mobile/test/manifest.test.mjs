import assert from "node:assert/strict";
import test from "node:test";
import {
  MAX_APPS,
  MAX_MANIFEST_BYTES,
  ManifestError,
  createCatalogClient,
  createMemoryCache,
  parseManifestText,
  validateManifest,
} from "../manifest.js";

const revision = "fc48ba487a1e0d0cd10b30d6600acd2895ffdbed";

function validManifest(overrides = {}) {
  return {
    schemaVersion: 1,
    prototype: true,
    label: "Local prototype",
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

function expectManifestError(action, code) {
  assert.throws(action, (error) => error instanceof ManifestError && (!code || error.code === code));
}

test("accepts the local prototype manifest and preserves the source pin", async () => {
  const text = await (await import("node:fs/promises")).readFile(new URL("../prototype-manifest.json", import.meta.url), "utf8");
  const manifest = parseManifestText(text);
  assert.equal(manifest.prototype, true);
  assert.equal(manifest.apps[0].id, "kneecap");
  assert.equal(manifest.apps[0].source.revision, revision);
  assert.equal(manifest.apps[0].routes.iphone.destination, null);
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
  const text = JSON.stringify(validManifest());
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
  const text = JSON.stringify(validManifest());
  const cache = createMemoryCache();
  let now = 10_000;
  const client = createCatalogClient({ cache, now: () => now, fetchImpl: async () => ({ ok: true, text: async () => text }) });
  await client.refresh();
  const cached = await client.load({ offline: true });
  assert.equal(cached.source, "cache");
  now += 25 * 60 * 60 * 1_000;
  const stale = await client.load({ offline: true });
  assert.equal(stale.stale, true);
  const emptyClient = createCatalogClient({ cache: createMemoryCache(), now: () => now, fetchImpl: async () => ({ ok: true, text: async () => text }) });
  await assert.rejects(() => emptyClient.load({ offline: true }), (error) => error.code === "offline-no-cache");
});

test("falls back to stale verified metadata after a network failure", async () => {
  const text = JSON.stringify(validManifest());
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
          releaseLock() {},
        };
      },
    },
  }) });
  await assert.rejects(() => client.refresh(), (error) => error.code === "manifest-too-large");
});
