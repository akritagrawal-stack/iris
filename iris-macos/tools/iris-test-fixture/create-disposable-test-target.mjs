import { execFileSync } from 'node:child_process';
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

// This helper creates one disposable Test-owned app. It never discovers or
// edits normal applications, marketplace data, credentials, or settings.
// The registry is changed only after the new source copy and both bundles pass
// local validation.

const fileManagerMode = 0o700;
const homeDirectory = os.homedir();
const supportRoot = path.join(homeDirectory, 'Library', 'Application Support', 'Iris Test');
const projectsRoot = path.join(supportRoot, 'Projects');
const applicationsRoot = path.join(projectsRoot, 'Apps');
const registryPath = path.join(supportRoot, 'test-projects.json');

function fail(message) {
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function canonicalExisting(pathname) {
  return realpathSync.native(pathname);
}

function assertCanonicalDirectory(pathname, label) {
  assert(path.isAbsolute(pathname), label + ' must be absolute');
  assert(path.resolve(pathname) === pathname, label + ' must be normalized');
  assert(canonicalExisting(pathname) === pathname, label + ' must not contain a symlink');
}

function writeText(pathname, contents, mode = 0o600) {
  writeFileSync(pathname, contents, { encoding: 'utf8', mode });
}

function run(command, arguments_, options = {}) {
  return execFileSync(command, arguments_, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options,
  }).trim();
}

function plistFor(bundleIdentifier, executableName, displayName, version) {
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    '<dict>',
    '  <key>CFBundleDisplayName</key>',
    '  <string>' + displayName + '</string>',
    '  <key>CFBundleExecutable</key>',
    '  <string>' + executableName + '</string>',
    '  <key>CFBundleIdentifier</key>',
    '  <string>' + bundleIdentifier + '</string>',
    '  <key>CFBundleInfoDictionaryVersion</key>',
    '  <string>6.0</string>',
    '  <key>CFBundleName</key>',
    '  <string>' + displayName + '</string>',
    '  <key>CFBundlePackageType</key>',
    '  <string>APPL</string>',
    '  <key>CFBundleShortVersionString</key>',
    '  <string>' + version + '</string>',
    '  <key>CFBundleVersion</key>',
    '  <string>' + version + '</string>',
    '  <key>LSMinimumSystemVersion</key>',
    '  <string>13.0</string>',
    '</dict>',
    '</plist>',
    '',
  ].join('\n');
}

const appSource = [
  'import AppKit',
  'import Foundation',
  '',
  'final class DisposableDeliveryAppDelegate: NSObject, NSApplicationDelegate {',
  '    private var window: NSWindow?',
  '',
  '    func applicationDidFinishLaunching(_ notification: Notification) {',
  '        let markerURL = Bundle.main.bundleURL.appendingPathComponent("Contents/fixture-marker.txt")',
  '        let marker = (try? String(contentsOf: markerURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"',
  '        let label = NSTextField(labelWithString: "Iris Test disposable delivery fixture\\n\\(marker)")',
  '        label.alignment = .center',
  '        label.font = .systemFont(ofSize: 20, weight: .medium)',
  '        label.translatesAutoresizingMaskIntoConstraints = false',
  '',
  '        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 220))',
  '        content.addSubview(label)',
  '        NSLayoutConstraint.activate([',
  '            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),',
  '            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),',
  '            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),',
  '        ])',
  '',
  '        let window = NSWindow(contentRect: content.bounds,',
  '                              styleMask: [.titled, .closable, .miniaturizable],',
  '                              backing: .buffered,',
  '                              defer: false)',
  '        window.title = "Iris Test disposable delivery fixture"',
  '        window.contentView = content',
  '        window.center()',
  '        window.makeKeyAndOrderFront(nil)',
  '        self.window = window',
  '        NSApp.activate(ignoringOtherApps: true)',
  '    }',
  '}',
  '',
  'let application = NSApplication.shared',
  'let delegate = DisposableDeliveryAppDelegate()',
  'application.delegate = delegate',
  'application.setActivationPolicy(.regular)',
  'application.run()',
  '',
].join('\n');

function shellQuote(value) {
  return "'" + value.replaceAll("'", "'\\\\''") + "'";
}

function buildScript({ appName, executableName, bundleIdentifier }) {
  return [
    '#!/bin/sh',
    'set -eu',
    '',
    'ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)',
    'APP_NAME=' + shellQuote(appName),
    'EXECUTABLE_NAME=' + shellQuote(executableName),
    'BUNDLE_IDENTIFIER=' + shellQuote(bundleIdentifier),
    'BUILD_ID="${IRIS_DISPOSABLE_FIXTURE_BUILD_ID:-fresh-$(date +%s)}"',
    'OUTPUT="$ROOT/release/mac-arm64/$APP_NAME.app"',
    'STAGING="$ROOT/release/.iris-disposable-build-$$"',
    '',
    'cleanup() {',
    '  rm -rf -- "$STAGING"',
    '}',
    'trap cleanup EXIT',
    '',
    'mkdir -p "$STAGING/Contents/MacOS"',
    '/usr/bin/xcrun swiftc -swift-version 5 -framework AppKit \\',
    '  "$ROOT/Sources/DisposableDeliveryApp.swift" \\',
    '  -o "$STAGING/Contents/MacOS/$EXECUTABLE_NAME"',
    '/bin/chmod 755 "$STAGING/Contents/MacOS/$EXECUTABLE_NAME"',
    'rm -rf -- "$OUTPUT"',
    'mkdir -p "$(dirname -- "$OUTPUT")"',
    'mkdir -p "$OUTPUT/Contents/MacOS"',
    '/usr/bin/ditto "$STAGING/Contents/MacOS/$EXECUTABLE_NAME" "$OUTPUT/Contents/MacOS/$EXECUTABLE_NAME"',
    'cat > "$OUTPUT/Contents/Info.plist" <<EOF',
    plistFor(bundleIdentifier, executableName, appName, '${BUILD_ID}'),
    'EOF',
    'printf "%s\\\\n" "$BUILD_ID" > "$OUTPUT/Contents/fixture-marker.txt"',
    'printf "%s\\\\n" "$OUTPUT"',
    '',
  ].join('\n');
}

function makeBundle({ artifactPath, sourceExecutable, bundleIdentifier, appName, version }) {
  const executableName = path.basename(sourceExecutable);
  const contentsRoot = path.join(artifactPath, 'Contents');
  const executablePath = path.join(contentsRoot, 'MacOS', executableName);
  mkdirSync(path.dirname(executablePath), { recursive: true, mode: fileManagerMode });
  run('/usr/bin/ditto', [sourceExecutable, executablePath]);
  chmodSync(executablePath, 0o755);
  writeText(path.join(contentsRoot, 'Info.plist'),
    plistFor(bundleIdentifier, executableName, appName, version));
  writeText(path.join(contentsRoot, 'fixture-marker.txt'), version);
}

function appendRegistryEntry(entry, existingData, existingEntries) {
  const lastBracket = existingData.lastIndexOf(']');
  assert(lastBracket >= 0 && existingData.slice(lastBracket + 1).trim() === '',
    'Test registry must be a JSON array with one final closing bracket');
  const beforeBracket = existingData.slice(0, lastBracket);
  const content = beforeBracket.trimEnd();
  const trailingWhitespace = beforeBracket.slice(content.length);
  const serializedEntry = JSON.stringify(entry, null, 2)
    .split('\n')
    .map(line => '  ' + line)
    .join('\n');
  const separator = existingEntries.length === 0 ? '' : ',';
  return content + separator + trailingWhitespace + serializedEntry + '\n]' + existingData.slice(lastBracket + 1);
}

function atomicallyAppendRegistry(entry, existingData, existingEntries) {
  const nextData = appendRegistryEntry(entry, existingData, existingEntries);
  const temporaryPath = registryPath + '.iris-disposable-' + process.pid + '-' + randomUUID() + '.tmp';
  const mode = statSync(registryPath).mode & 0o777;
  try {
    writeFileSync(temporaryPath, nextData, { encoding: 'utf8', mode });
    chmodSync(temporaryPath, mode);
    renameSync(temporaryPath, registryPath);
  } finally {
    if (existsSync(temporaryPath)) rmSync(temporaryPath, { force: true });
  }
}

function validateBundle(bundlePath, bundleIdentifier) {
  assert(path.isAbsolute(bundlePath) && path.resolve(bundlePath) === bundlePath,
    'bundle path is not canonical: ' + bundlePath);
  assert(bundlePath.endsWith('.app'), 'bundle path must end in .app: ' + bundlePath);
  assert(canonicalExisting(bundlePath) === bundlePath, 'bundle path contains a symlink: ' + bundlePath);
  const infoPath = path.join(bundlePath, 'Contents', 'Info.plist');
  const executablePath = path.join(bundlePath, 'Contents', 'MacOS', 'IrisDisposableDelivery');
  const info = run('/usr/bin/plutil', ['-convert', 'json', '-o', '-', '--', infoPath]);
  const json = JSON.parse(info);
  assert(json.CFBundleIdentifier === bundleIdentifier, 'wrong bundle identity in ' + bundlePath);
  assert(json.CFBundleExecutable === 'IrisDisposableDelivery', 'wrong executable in ' + bundlePath);
  const metadata = statSync(executablePath);
  assert(metadata.isFile() && (metadata.mode & 0o111) !== 0,
    'bundle executable is not runnable: ' + bundlePath);
}

function main() {
  assert(process.platform === 'darwin', 'This fixture creator is macOS-only');
  assertCanonicalDirectory(homeDirectory, 'home directory');
  assertCanonicalDirectory(supportRoot, 'Iris Test support root');
  assertCanonicalDirectory(projectsRoot, 'Iris Test Projects root');
  assertCanonicalDirectory(applicationsRoot, 'Iris Test Apps root');
  assert(path.resolve(registryPath) === registryPath, 'registry path must be normalized');
  assert(canonicalExisting(path.dirname(registryPath)) === path.dirname(registryPath),
    'registry parent must not contain a symlink');

  const existingData = readFileSync(registryPath, 'utf8');
  const existingEntries = JSON.parse(existingData);
  assert(Array.isArray(existingEntries), 'Iris Test registry must contain an array');
  assert(existingEntries.length < 12, 'Iris Test registry has no disposable-entry capacity');
  const existingSlugs = new Set(existingEntries.map(entry => entry.slug));
  const existingBundleIds = new Set(existingEntries.map(entry => entry.bundleIdentifier));
  const suffix = randomUUID().replaceAll('-', '').slice(0, 12);
  const slug = 'iris-delivery-' + suffix;
  const appName = 'Iris Test Delivery ' + suffix;
  const executableName = 'IrisDisposableDelivery';
  const bundleIdentifier = 'com.publikhq.iris.test.delivery-' + suffix;
  assert(!existingSlugs.has(slug) && !existingBundleIds.has(bundleIdentifier), 'disposable identity collided');

  const clonePath = path.join(projectsRoot, slug);
  const applicationPath = path.join(applicationsRoot, appName + '.app');
  const buildArtifactPath = path.join(clonePath, 'release', 'mac-arm64', appName + '.app');
  const createdPaths = [clonePath, applicationPath];
  assert(!existsSync(clonePath) && !existsSync(applicationPath), 'disposable target path already exists');
  mkdirSync(path.join(clonePath, 'Sources'), { recursive: true, mode: fileManagerMode });
  mkdirSync(path.join(clonePath, 'scripts'), { recursive: true, mode: fileManagerMode });

  try {
    writeText(path.join(clonePath, 'Sources', 'DisposableDeliveryApp.swift'), appSource);
    writeText(path.join(clonePath, 'scripts', 'build-mac.sh'),
      buildScript({ appName, executableName, bundleIdentifier }), 0o700);
    writeText(path.join(clonePath, '.gitignore'), ['release/', ''].join('\n'), 0o600);
    writeText(path.join(clonePath, 'electron-builder.cjs'),
      '// Electron stack marker for Iris Test packaging detection.\n');
    writeText(path.join(clonePath, 'package.json'), JSON.stringify({
      name: slug,
      private: true,
      version: '1.0.0',
      scripts: { 'dist:mac': './scripts/build-mac.sh' },
    }, null, 2) + '\n');

    run('git', ['-C', clonePath, 'init', '-b', 'main']);
    run('git', ['-C', clonePath, 'config', 'user.name', 'Iris Test disposable fixture']);
    run('git', ['-C', clonePath, 'config', 'user.email', 'iris-test-fixture@localhost']);
    run('git', ['-C', clonePath, 'add', '--all']);
    run('git', ['-C', clonePath, 'commit', '-m', 'fixture: initial disposable delivery target']);
    const pinnedCommit = run('git', ['-C', clonePath, 'rev-parse', 'HEAD']);
    assert(/^[0-9a-f]{40}$/.test(pinnedCommit), 'fixture commit is not a full SHA-1');

    const temporaryBuildRoot = path.join(clonePath, 'release', '.iris-initial-build-' + process.pid);
    mkdirSync(temporaryBuildRoot, { recursive: true, mode: fileManagerMode });
    const sourceExecutable = path.join(temporaryBuildRoot, executableName);
    run('/usr/bin/xcrun', ['swiftc', '-swift-version', '5', '-framework', 'AppKit',
      path.join(clonePath, 'Sources', 'DisposableDeliveryApp.swift'), '-o', sourceExecutable]);
    chmodSync(sourceExecutable, 0o755);
    mkdirSync(path.dirname(buildArtifactPath), { recursive: true, mode: fileManagerMode });
    makeBundle({ artifactPath: buildArtifactPath, sourceExecutable, bundleIdentifier, appName, version: 'build-1' });
    makeBundle({ artifactPath: applicationPath, sourceExecutable, bundleIdentifier, appName, version: 'stable-1' });
    rmSync(temporaryBuildRoot, { recursive: true, force: true });
    validateBundle(applicationPath, bundleIdentifier);
    validateBundle(buildArtifactPath, bundleIdentifier);
    assert(canonicalExisting(clonePath) === clonePath, 'clone path contains a symlink');
    assert(buildArtifactPath.startsWith(clonePath + '/'), 'artifact escaped the clone');
    assert(applicationPath.startsWith(applicationsRoot + '/'), 'stable app escaped the Apps root');

    const entry = {
      slug,
      name: appName,
      clonePath,
      applicationPath,
      buildArtifactPath,
      bundleIdentifier,
      pinnedCommit,
    };
    atomicallyAppendRegistry(entry, existingData, existingEntries);
    const rereadEntries = JSON.parse(readFileSync(registryPath, 'utf8'));
    assert(rereadEntries.length === existingEntries.length + 1, 'registry entry count did not increase by one');
    assert(JSON.stringify(rereadEntries.slice(0, existingEntries.length)) === JSON.stringify(existingEntries),
      'existing registry entries changed');
    assert(rereadEntries.at(-1).slug === slug, 'new registry entry was not appended');

    console.log(JSON.stringify({
      status: 'created',
      slug,
      name: appName,
      clonePath,
      applicationPath,
      buildArtifactPath,
      bundleIdentifier,
      pinnedCommit,
      registryPath,
      existingEntryCount: existingEntries.length,
      registryEntryCount: rereadEntries.length,
      editDeliveryInvoked: false,
      applicationsLaunched: false,
      marketplaceTouched: false,
    }, null, 2));
  } catch (error) {
    for (const pathname of createdPaths.reverse()) {
      if (existsSync(pathname)) rmSync(pathname, { recursive: true, force: true });
    }
    throw error;
  }
}

try {
  main();
} catch (error) {
  console.error('DISPOSABLE TEST TARGET NOT CREATED: ' + error.message);
  process.exitCode = 1;
}
