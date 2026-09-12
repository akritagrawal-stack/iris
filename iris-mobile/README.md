# Iris mobile install hub prototype

This is a dependency-free, phone-sized catalog and route discovery prototype. It reads only the small local `prototype-manifest.json`; it does not install software, fetch binaries, register a service worker, collect usage, or claim a web editor.

From the repository root, serve it locally:

```sh
node iris-mobile/server.mjs --port 4173
```

Open [http://127.0.0.1:4173/](http://127.0.0.1:4173/) in a browser and use a phone viewport. Choose iPhone, Android, or Computer, then use Refresh. The route is Setup needed because the observed catalog has no verified native distribution URL. The manifest keeps Kneecap’s observed guide slug, repository, and source pin (`fc48ba487a1e0d0cd10b30d6600acd2895ffdbed`).

The validator enforces a 64 KiB manifest, 32 app, 240 character text, 80 character title, and 2,048 character URL limit. Cache metadata is capped at 64 KiB and one day old; it contains only the verified manifest text and timestamp. Concurrent refreshes share one request. No service worker or background binary request is present.

Run the focused checks with `node --test iris-mobile/test/*.test.mjs` or `pnpm test:mobile`.
