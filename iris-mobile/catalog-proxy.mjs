import { LIVE_CATALOG_UPSTREAM, MAX_MANIFEST_BYTES, SERVER_CACHE_MAX_AGE_MS, parseCatalogText } from "./manifest.js";

export const SERVER_CATALOG_TIMEOUT_MS = 5_000;

async function readChunk(reader, signal) {
  if (!signal) return reader.read();
  if (signal.aborted) throw signal.reason || new Error("catalog request aborted");
  return new Promise((resolve, reject) => {
    let settled = false;
    const onAbort = () => {
      settled = true;
      signal.removeEventListener("abort", onAbort);
      reject(signal.reason || new Error("catalog request aborted"));
    };
    signal.addEventListener("abort", onAbort, { once: true });
    reader.read().then((value) => {
      if (settled) return;
      settled = true;
      signal.removeEventListener("abort", onAbort);
      resolve(value);
    }, (error) => {
      if (settled) return;
      settled = true;
      signal.removeEventListener("abort", onAbort);
      reject(error);
    });
  });
}

async function readBoundedBody(response, signal) {
  if (!response.body || typeof response.body.getReader !== "function") {
    const text = await response.text();
    if (new TextEncoder().encode(text).byteLength > MAX_MANIFEST_BYTES) throw new Error("catalog response too large");
    return text;
  }
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await readChunk(reader, signal);
      if (done) break;
      if (!(value instanceof Uint8Array)) throw new Error("catalog response contains invalid bytes");
      size += value.byteLength;
      if (size > MAX_MANIFEST_BYTES) throw new Error("catalog response too large");
      chunks.push(value);
    }
  } catch (error) {
    Promise.resolve(reader.cancel?.(error)).catch(() => {});
    throw error;
  } finally {
    reader.releaseLock?.();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder().decode(bytes);
}

export function createCatalogProxy({ fetchImpl = globalThis.fetch, now = () => Date.now(), timeoutMs = SERVER_CATALOG_TIMEOUT_MS, setTimeoutImpl = globalThis.setTimeout, clearTimeoutImpl = globalThis.clearTimeout } = {}) {
  if (typeof fetchImpl !== "function") throw new TypeError("fetchImpl is required");
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) throw new TypeError("timeoutMs must be positive");
  let catalogCache = null;
  let catalogInFlight = null;
  let requestCount = 0;

  async function fetchCatalog() {
    if (catalogInFlight) return catalogInFlight;
    if (catalogCache && now() - catalogCache.savedAt < SERVER_CACHE_MAX_AGE_MS) return catalogCache;
    catalogInFlight = (async () => {
      requestCount += 1;
      const controller = new AbortController();
      const timeout = setTimeoutImpl(() => controller.abort(new Error("catalog request timed out")), timeoutMs);
      try {
        const upstream = await fetchImpl(LIVE_CATALOG_UPSTREAM, { method: "GET", redirect: "error", headers: { Accept: "application/json" }, signal: controller.signal });
        if (!upstream.ok) throw new Error(`upstream status ${upstream.status}`);
        const text = await readBoundedBody(upstream, controller.signal);
        const savedAt = now();
        parseCatalogText(text, { observedAt: new Date(savedAt).toISOString() });
        catalogCache = { text, savedAt };
        return catalogCache;
      } finally {
        clearTimeoutImpl(timeout);
        catalogInFlight = null;
      }
    })();
    return catalogInFlight;
  }

  return { fetchCatalog, get requestCount() { return requestCount; } };
}
