# Iris mobile install hub prototype

This is a dependency-free, phone-sized catalog and route discovery hub. Its default source is the fixed same-origin `/api/iris/apps` endpoint, which serves the bounded public Publik catalog. It does not install software, fetch binaries, register a service worker, collect usage, or claim a web editor.

From the repository root, serve it locally:

```sh
node iris-mobile/server.mjs --port 4177
```

Open [http://127.0.0.1:4177/](http://127.0.0.1:4177/) in a browser and use a phone viewport. Choose iPhone, Android, or Computer, then use Refresh. The route is Setup needed because the observed catalog has no verified native distribution URL. The upstream response observed on September 12, 2026 contains `slug`, `name`, `macBundleId`, `latestReleaseTag`, and `guideSlug`; it has no native destination or source commit pin. The UI shows those unknowns explicitly.

The validator enforces a 64 KiB manifest, 32 displayed apps, 240 character text, 80 character title, and 2,048 character URL limit. If the upstream catalog exceeds 32 apps, the hub shows the first 32 and the total count. The server proxy uses only `https://publikhq.com/api/iris/apps`, times out after five seconds, bounds streamed bytes, coalesces concurrent upstream requests, validates before caching, and keeps a five-minute metadata cache. Browser cache metadata is capped at 64 KiB and one day old; it contains only the raw verified catalog response and timestamp. Concurrent refreshes share one request. No service worker or background binary request is present.

Tests can opt into the small fixture with `createCatalogClient({ fixture: true })` or parse it with `parseCatalogText`. Production and fixture responses use the same mapper. The fixture is not a distribution route.

Run the focused checks with `node --test iris-mobile/test/*.test.mjs` or `pnpm test:mobile`.
