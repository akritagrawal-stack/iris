# Live mobile catalog evidence, September 12, 2026

At `2026-09-12T23:24:09Z`, `GET https://publikhq.com/api/iris/apps` returned HTTP 200 and 3,011 bytes of JSON. The response contained 26 app records with these observed fields only: `slug`, `name`, `macBundleId`, `latestReleaseTag`, and `guideSlug`. It contained no icon, iPhone or Android destination, computer destination, repository URL, or commit pin.

`iris-mobile/manifest.js` maps that response and the opt-in `prototype-manifest.json` fixture through the same mapper. A present Mac bundle ID records observed computer identity, while every route remains `unavailable` until a verified HTTPS destination is supplied. `latestReleaseTag` remains a release tag, and a missing commit pin remains `null` and renders as unknown. Icons use a validated observed URL when supplied and a title fallback otherwise.

The static server exposes only the fixed same-origin `/api/iris/apps` path. Its upstream URL, five-second timeout, 64 KiB streamed response bound, five-minute short cache, and request coalescing are bounded in code. No arbitrary proxy URL or credential is accepted.

Node verification: `node --test iris-mobile/test/*.test.mjs` passed 14 tests covering live mapping, opt-in fixture mapping, missing fields, valid and unsafe icons/routes, malformed and oversized input, duplicate IDs, request coalescing, stale offline cache, network fallback, and streamed bounds.

This proves catalog metadata and route discovery. Publisher work remains for signed TestFlight or App Store distribution, a signed Android package or Play listing, and a verified computer destination. No native package was signed, installed, launched, or accepted on a phone.
