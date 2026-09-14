# Mobile hub acceptance, September 12

Scope: local static hub at `http://127.0.0.1:4177/`, integrated M1 source and
the follow-up UI corrections. This is browser acceptance of the install-route
hub. No iPhone/Android package was installed, signed or published.

- Executed all eight Node manifest/cache checks: passed. These cover unsafe and
  forged routes, malformed/oversized data, request coalescing, bounded streamed
  responses and offline/cache behavior.
- Used the actual in-app browser at 390 x 844. The Kneecap card fits without
  horizontal overflow. iPhone, Android and Computer selection gives the correct
  unavailable route and never offers an invented Install button.
- Stopped the local HTTP server and clicked Refresh. The cached card stayed
  usable and a visible refresh-failure warning appeared.
- Found a real defect: switching devices then replaced the warning with a
  generic device status. Fixed the shared status update and repeated this
  journey. The stale warning now survives Android selection and keyboard
  Tab/Space selection of Computer.
- Restarted the HTTP server and clicked Refresh. The warning cleared only
  after successful retrieval. No forced network retry loop was added.
- A setup link with a new-tab target produced no visible navigation in the
  in-app browser. Changed this guide link to ordinary same-tab navigation.
  Clicking it opened the real `https://publikhq.com/kneecap` page, including its
  installation guide links. Browser Back returned to the hub.
- Moved source hashes and publisher chores into a collapsed, explicitly
  labeled publisher section. The main card tells a reader the current route
  and next available action.
- Restored the browser viewport after testing. The local prototype remains
  open as a deliverable.

The prototype manifest is clearly labeled and is not a live Publik catalog
adapter. Signed distribution destinations, on-device installation, app launch,
media permissions, background/resume and export remain untested. Current
Kneecap source capabilities and a working setup hyperlink do not establish any
of those outcomes.

## Current hub routing observation, September 14

The running hub at `http://127.0.0.1:4177/` loaded the live catalog with **27
apps**, including `kneecap`. Through the UI, switching iPhone to Android and
then Computer updated the selected-device state and every app's support message
without a page reload. Refresh returned to a ready catalog state. The current
catalog truthfully reports `support unknown` and no download route for these
devices, so this verifies routing and fail-closed messaging only; it does not
prove an install, open, restart, or physical-device journey.

## Current published Kneecap iPhone guide observation, September 14

The visible published guide exposes a 17-step Mac+iPhone path pinned to reviewed
commit `fc48ba4`, including Git/Node/Bun checks, source validation, `bun install`,
mobile build, Capacitor sync/open, Apple signing, device trust, and export
verification. It explicitly states that the mobile shell is not yet present in
the Kneecap repository and that the build is pre-release with seven-day
unsigned provisioning. The guide still uses `~/kneecap` as its source location
and refuses a non-clean or wrong-origin folder. This is useful source and UX
evidence, but it confirms that the actual iPhone install journey remains
unverified and that multiple local Kneecap folders need Iris workspace selection
rather than blind path reuse.
