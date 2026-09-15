import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { dirname, extname, join, normalize, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createCatalogProxy } from "./catalog-proxy.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)));
const portArgument = process.argv.indexOf("--port");
const port = Number(portArgument >= 0 ? process.argv[portArgument + 1] : process.env.IRIS_MOBILE_PORT || 4173);
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8" };
const allowedFiles = new Set(["index.html", "app.js", "manifest.js", "prototype-manifest.json", "styles.css"]);
const catalogPath = "/api/iris/apps";
const catalogProxy = createCatalogProxy();

const server = createServer(async (request, response) => {
  try {
    const requestPath = new URL(request.url || "/", "http://localhost").pathname;
    if (requestPath === catalogPath) {
      if (request.method !== "GET") { response.writeHead(405); response.end("Method not allowed"); return; }
      try {
        const result = await catalogProxy.fetchCatalog();
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
