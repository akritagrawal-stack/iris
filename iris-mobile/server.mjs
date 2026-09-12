import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { dirname, extname, join, normalize, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { LIVE_CATALOG_UPSTREAM, MAX_MANIFEST_BYTES, SERVER_CACHE_MAX_AGE_MS } from "./manifest.js";

const root = resolve(dirname(fileURLToPath(import.meta.url)));
const portArgument = process.argv.indexOf("--port");
const port = Number(portArgument >= 0 ? process.argv[portArgument + 1] : process.env.IRIS_MOBILE_PORT || 4173);
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8" };
const allowedFiles = new Set(["index.html", "app.js", "manifest.js", "prototype-manifest.json", "styles.css"]);
const catalogPath = "/api/iris/apps";
const upstreamTimeoutMs = 5_000;
let catalogCache = null;
let catalogInFlight = null;

async function readBoundedBody(response) {
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
      const { done, value } = await reader.read();
      if (done) break;
      if (!(value instanceof Uint8Array)) throw new Error("catalog response contains invalid bytes");
      size += value.byteLength;
      if (size > MAX_MANIFEST_BYTES) throw new Error("catalog response too large");
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

async function fetchCatalog() {
  if (catalogInFlight) return catalogInFlight;
  if (catalogCache && Date.now() - catalogCache.savedAt < SERVER_CACHE_MAX_AGE_MS) return catalogCache;
  catalogInFlight = (async () => {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), upstreamTimeoutMs);
    try {
      const upstream = await fetch(LIVE_CATALOG_UPSTREAM, { method: "GET", headers: { Accept: "application/json" }, signal: controller.signal });
      if (!upstream.ok) throw new Error(`upstream status ${upstream.status}`);
      const text = await readBoundedBody(upstream);
      catalogCache = { text, savedAt: Date.now() };
      return catalogCache;
    } finally {
      clearTimeout(timeout);
      catalogInFlight = null;
    }
  })();
  return catalogInFlight;
}

const server = createServer(async (request, response) => {
  try {
    const requestPath = new URL(request.url || "/", "http://localhost").pathname;
    if (requestPath === catalogPath) {
      if (request.method !== "GET") { response.writeHead(405); response.end("Method not allowed"); return; }
      try {
        const result = await fetchCatalog();
        response.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Content-Length": Buffer.byteLength(result.text), "Cache-Control": "no-store" });
        response.end(result.text);
      } catch (error) {
        response.writeHead(502, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" });
        response.end(`Catalog upstream unavailable: ${error instanceof Error ? error.message : "request failed"}`);
      }
      return;
    }
    const relativePath = requestPath === "/" ? "index.html" : requestPath.replace(/^\/+/, "");
    const filePath = normalize(join(root, relativePath));
    const relativeFile = relative(root, filePath);
    if (relativeFile.startsWith("..") || relativeFile.includes(".." + requireSeparator()) || !allowedFiles.has(relativeFile)) {
      response.writeHead(404); response.end("Not found"); return;
    }
    const fileStat = await stat(filePath);
    if (!fileStat.isFile()) throw new Error("not a file");
    const body = await readFile(filePath);
    response.writeHead(200, { "Content-Type": types[extname(filePath)] || "application/octet-stream", "Content-Length": body.byteLength, "Cache-Control": "no-store" });
    response.end(body);
  } catch {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Not found");
  }
});

function requireSeparator() { return process.platform === "win32" ? "\\" : "/"; }

server.listen(port, "127.0.0.1", () => {
  console.log(`Iris mobile hub: http://127.0.0.1:${port}/`);
  console.log(`Serving ${root}`);
});
