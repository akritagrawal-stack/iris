# Disposable Iris Test delivery fixture

create-disposable-test-target.mjs creates one native, launchable macOS app
copy under the Iris Test-owned Projects directory and appends one registry
entry. It is intended for an operator-approved update, relaunch, and Undo
acceptance run.

The helper is deliberately narrow:

- it requires the real Iris Test support roots and rejects symlinked paths;
- it creates a unique source copy with a clean Git commit, a stable app under
  Projects/Apps, and a fresh artifact under that clone;
- it uses an Electron-shaped package manifest so Iris can resolve the existing
  dist:mac packaging route, while the fixture build produces a tiny native
  AppKit window;
- it appends the registry entry atomically and verifies the existing entries
  are value-for-value equivalent as parsed JSON values;
- it does not launch an app, invoke Iris edit or delivery, inspect credentials,
  touch marketplace data, or modify normal app installations.

Run from the repository root:

~~~sh
node iris-macos/tools/iris-test-fixture/create-disposable-test-target.mjs
~~~

The command prints the exact slug, clone, stable application, fresh artifact,
bundle identifier, pinned commit, and registry path. Keep those values with the
acceptance evidence. The existing registry is capacity-limited to twelve
entries, so the helper refuses when there is no slot.

The generated app displays the marker stored in its bundle. A later
operator-approved npm run dist:mac from the generated clone creates a fresh
artifact at the registered path; Iris Test must still recheck the registered
source identity and stopped process before delivery. Do not use the helper's
target as a normal Iris or marketplace installation.
