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
