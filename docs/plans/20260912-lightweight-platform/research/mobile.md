# Iris mobile installer/runtime shell: bounded research

**Date:** 2026-09-12  
**Decision:** choose a web-first runtime with a narrow native bridge for Kneecap; treat iPhone native installation as a signing/deployment problem, not as a general app-hosting problem.

## Recommendation

The smallest useful MVP is one iPhone app: a signed Capacitor shell containing a bundled Kneecap web build, a local catalog with exactly one first-party entry, and a small native bridge for media import, local storage, export, and device diagnostics. Add an optional Mac companion that builds and deploys this app to the owner’s iPhone. Keep the catalog and installer abstractions ready for Android, but do not promise installation of arbitrary iOS native apps or code from a remote catalog.

There are three distinct products hiding in “mobile shell”:

1. A PWA/Home Screen web app: no native install or signing, but browser/WebKit limits apply.
2. A native web shell: one signed iOS/Android binary that runs bundled web assets and calls explicitly implemented native plugins.
3. An app distributor: installs separate native app packages. Each native app retains its own bundle identity, signature, entitlements, permissions, and distribution review. A shell cannot erase those boundaries.

## iPhone constraints

Apple’s current review rules are decisive. Guideline 2.5.2 says an app should be self-contained and may not download, install, or execute code that changes the app’s features or functionality, including other apps. Guideline 2.5.6 requires apps that browse the web to use WebKit, with alternative browser engines requiring an entitlement. Guideline 2.5.8 says apps creating alternate desktop or Home Screen environments will be rejected. ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/))

Apple does provide a bounded exception in 4.7: apps may offer HTML5/JavaScript mini apps, mini games, streaming games, chatbots, and plug-ins. The host remains responsible for those offerings; it must provide privacy controls, objectionable-content filtering, reporting and blocking, age controls, an index and universal links, and must not expose native APIs to individual mini apps without Apple’s permission. This can support a reviewed “approved web experiences” catalog, but it is not permission to load arbitrary native applications or an assurance of App Review approval. The shell must expose no Capacitor/native bridge to catalog content.

`WKWebView` can load a URL request or local files/HTML and embedded resources, so a bundled static web runtime is technically straightforward. ([WKWebView](https://developer.apple.com/documentation/webkit/wkwebview/)) A Safari PWA can be added to the Home Screen with an icon and standalone presentation, but remains a web app; it cannot provide Kneecap’s native media/export bridge. ([Configuring Web Applications](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html))

TestFlight is a beta distribution channel, not a review bypass: Apple says TestFlight submissions should be intended for public distribution and comply with the App Review Guidelines. ([TestFlight](https://developer.apple.com/testflight/)) A free Apple account supports on-device testing for personal use through Xcode, with periodic re-provisioning; the paid Apple Developer Program is $99 per year and unlocks distribution, TestFlight, and ad hoc capabilities. ([Choosing a Membership](https://developer.apple.com/support/compare-memberships/)) Apple also documents seven-day offline development/ad hoc profiles for eligible teams. ([Provisioning profile updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates)) A remote Mac can automate Xcode builds and deployment, but it still needs the user’s team, certificates/profiles, device trust, and often an online verification step. It cannot make unsigned or foreign native apps launch.

Apple’s alternative website/marketplace distribution is region and entitlement constrained. Marketplace apps need Apple approval, a website owned by the marketplace, developer relationships/tokens, notarization, and licensing; apps distributed that way still arrive as signed installable app packages. ([Distributing your app on an alternative marketplace](https://developer.apple.com/documentation/marketplacekit/distributing-your-app-on-an-alternative-marketplace), [Create a marketplace app](https://developer.apple.com/help/app-store-connect/managing-alternative-distribution/create-a-marketplace-app)) This is a later distribution strategy, not the MVP and not a universal iPhone sideload path.

## Android constraints

Android is materially more permissive, but installation is still system-mediated. `PackageInstaller` stages one or more APKs and commits an install or update; normal commits may require user intervention. Updates require matching package name, version code, and signing certificates. ([PackageInstaller](https://developer.android.com/reference/android/content/pm/PackageInstaller), [PackageInstaller.Session](https://developer.android.com/reference/android/content/pm/PackageInstaller.Session)) For an app targeting API 26+, launching the old installer intent requires `REQUEST_INSTALL_PACKAGES`; Android 8+ uses a per-source “install unknown apps” setting, exposed through `canRequestPackageInstalls()`. ([Manifest.permission](https://developer.android.com/reference/android/Manifest.permission), [Android 8.0 behavior changes](https://developer.android.com/about/versions/oreo/android-8.0-changes))

Therefore an Android Iris companion can download, hash-check, stage, and hand off an APK to PackageInstaller, then report the system result. It cannot silently install arbitrary apps for an ordinary user. Android’s developer-verification rollout also deserves a shipping-time check: Google’s current guidance starts regional enforcement on 2026-09-30 and expands globally in 2027; direct sideload remains available, but unverified developers may require an advanced flow. ([Android developer verification](https://developer.android.com/developer-verification/guides), [rollout announcement](https://developer.android.com/blog/posts/android-developer-verification-rolling-out-to-all-developers-on-play-console-and-android-developer-console))

## Kneecap inspection

The local `/Users/akrit/kneecap` checkout is detached at `fc48ba48` (2026-08-23) and already dirty: modified `bun.lock`, plus untracked `.DS_Store` files. No files were changed, dependencies installed, secrets read, or commands run against a device. The public repository is [Blueturboguy07/kneecap](https://github.com/Blueturboguy07/kneecap), forked from OpenCut classic.

The relevant local evidence is:

- [`apps/mobile/capacitor.config.ts`](/Users/akrit/kneecap/apps/mobile/capacitor.config.ts) sets `webDir: "www"`, has no `server.url`, and configures a local secure Android WebView origin. The intended runtime is a bundled Vite build, not a remote development page.
- [`apps/mobile/package.json`](/Users/akrit/kneecap/apps/mobile/package.json) uses Capacitor 8 for iOS and Android, React, Vite, `@kneecap/mobile-ui`, `@kneecap/editor-core`, `@kneecap/native-bridge`, `mediabunny`, and a local `opencut-wasm` package.
- The web side has a real editor entry in [`apps/mobile/src/app/app-root.tsx`](/Users/akrit/kneecap/apps/mobile/src/app/app-root.tsx), a Vite/WASM build, and a crash boundary. The shipped `www` snapshot is about 26 MB; the mobile directory is about 75 MB including native/project artifacts. These are checkout sizes, not a final compressed download size.
- The shared bridge in [`packages/native-bridge/src/types.ts`](/Users/akrit/kneecap/packages/native-bridge/src/types.ts) is the right seam: `getMediaRoot`, `toPlaybackUri`, `pickMedia`, `generateProxy`, `generateThumbnails`, `exportProject`, `transcribe`, `capabilities`, and native audio methods. The contract intentionally passes JSON metadata, progress events, and URLs rather than video bytes.
- iOS has app-local plugin registration in [`SceneDelegate.swift`](/Users/akrit/kneecap/apps/mobile/ios/App/App/SceneDelegate.swift), PHPicker/media custody, AVFoundation proxy/export code, native audio, and Apple Speech transcription sources. Android has a registered Capacitor plugin, Photo Picker/SAF and camera intents, Media3 export/transcode sources, and Whisper JNI scaffolding.
- The model directories are empty in this checkout. The build script says Whisper GGML weights are fetched at build time and are roughly 74–142 MB; Android also documents that no native `.so` is bundled yet. Thus source presence is not runtime acceptance. The iOS plugin header/README still says transcription is stubbed while the local tree registers `transcribe` and contains Apple Speech code. This inconsistency should be resolved before claiming capability.

The public [`apps/mobile/README.md`](https://github.com/Blueturboguy07/kneecap/blob/main/apps/mobile/README.md) records prior simulator/build evidence but also says the shell was a harness and transcription was stubbed. The local source has since moved further, so use the README as historical evidence and require a fresh physical-device run for current claims.

## Runtime choices and open-source references

**Capacitor is the best fit for Kneecap.** It drops into an existing web app, packages local assets, and gives Swift/Kotlin/JavaScript plugin seams. The upstream project describes exactly this web-first native runtime and plugin API. ([Capacitor docs](https://capacitorjs.com/docs), [ionic-team/capacitor](https://github.com/ionic-team/capacitor)) It matches Kneecap’s Vite/DOM/WASM architecture and keeps native media/export code explicit.

**Expo Go is a development playground, not a universal runtime.** Expo Go has a fixed native library set; adding a native library or changing app identity requires a custom development build. ([Expo development-build FAQ](https://docs.expo.dev/develop/development-builds/faq/), [expo/expo](https://github.com/expo/expo)) Expo’s EAS Update can swap JavaScript/assets without reinstalling, but only when the update matches the binary’s `runtimeVersion`; native changes require a new build. ([Runtime versions](https://docs.expo.dev/eas-update/runtime-versions/), [EAS Update](https://docs.expo.dev/eas-update/introduction/)) Expo would be sensible for a future React Native catalog, but migrating Kneecap’s DOM/WASM UI adds unnecessary cost for this MVP.

**AltStore demonstrates a signing companion, not a signing escape hatch.** Its open-source app sideloads `.ipa` files using an Apple ID, which is useful prior art for UX and renewal reminders, while preserving Apple’s signing limits. ([altstoreio/AltStore](https://github.com/altstoreio/AltStore)) **PWABuilder** is useful reference for packaging a web app into platform wrappers, but a generated wrapper still has the same iOS review/signing rules. ([pwa-builder/PWABuilder](https://github.com/pwa-builder/PWABuilder), [pwa-builder/pwabuilder-ios](https://github.com/pwa-builder/pwabuilder-ios))

## Proposed modules

Keep these interfaces platform-neutral and implement only the iOS paths in MVP:

```ts
type AppKind = "bundled-web" | "reviewed-web" | "native-package";
interface AppDescriptor { id: string; version: string; kind: AppKind; url?: string;
  sha256?: string; runtimeVersion: string; capabilities: string[]; }
interface AppCatalog { list(): Promise<AppDescriptor[]>; resolve(id: string): Promise<AppDescriptor>; }
interface WebRuntime { mount(app: AppDescriptor): Promise<void>; unload(): Promise<void>; }
interface InstallCoordinator {
  inspect(app: AppDescriptor): Promise<{ supported: boolean; reason?: string }>;
  install(app: AppDescriptor): AsyncGenerator<"download"|"awaiting-user"|"done"|"error">;
}
interface BuildCompanion {
  pair(): Promise<{ deviceId: string; osVersion: string }>;
  buildAndDeploy(req: { appId: string; sourceRef: string }): AsyncGenerator<"building"|"signing"|"installing"|"done"|"error">;
}
interface UpdateManager { check(appId: string, runtimeVersion: string): Promise<AppDescriptor|null>;
  applyWebUpdate(app: AppDescriptor): Promise<void>; rollback(appId: string): Promise<void>; }
```

For iOS, `InstallCoordinator.inspect` must return `supported: false` for `native-package`; native installation delegates to `BuildCompanion` or Apple’s approved channel. For Android, it can use PackageInstaller and surface `awaiting-user`. Web packages need a signed manifest, hash, runtime version, declared capability list, size, minimum OS, and rollback metadata. A reviewed catalog package gets no native bridge and cannot become a hidden app update channel.

## Capability tiers, costs, and storage

- **Tier 0, PWA:** lowest cost and storage; hosted web assets, no native build, no media custody/export guarantees. Good fallback and preview.
- **Tier 1, bundled shell (MVP):** one Capacitor binary per platform, local web assets, WASM, and only the Kneecap native bridge. iOS requires Xcode/macOS and signing; a paid Apple membership is $99/year for distribution, while free personal testing requires periodic re-provisioning. Android requires Gradle/SDK/keystore and user-approved sideload unless Play-distributed.
- **Tier 2, reviewed web catalog:** one signed host plus HTML5/JS packages that stay inside the web sandbox. App Review exposure increases under 4.7; content moderation, age controls, reporting, privacy, index, and universal links become product work. Downloaded package storage is additive and must be quota-aware.
- **Tier 3, native app catalog:** each app has a separate binary/signing/distribution pipeline. Storage, review, permissions, and updates scale per app. This is not an iOS shell feature; it is an app distribution platform.

Kneecap’s native video pipeline already needs substantial device storage for originals, proxies, thumbnails, exports, and possibly speech models. Keep model weights optional and platform-specific until physical-device transcription acceptance; a 74–142 MB model can exceed the shell’s own compressed size. Store only relative media paths plus content hashes, because iOS container identifiers can change across reinstall/update.

## Failure and upgrade behavior

Use typed errors: `UNSUPPORTED`, `PERMISSION_DENIED`, `USER_CANCELLED`, `SIGNING_REQUIRED`, `USER_ACTION_REQUIRED`, `INCOMPATIBLE_RUNTIME`, `BAD_SIGNATURE`, `HASH_MISMATCH`, `STORAGE_FULL`, `OFFLINE`, and `IO_ERROR`. Show the next user action and preserve the last working app. Handle expired/revoked iOS profiles, missing device trust, disconnected Mac, Android unknown-source denial, PackageInstaller conflicts, mismatched signing keys, low storage, corrupt downloads, offline first launch, missing model/ABI, denied Photos/camera/microphone, interrupted proxy/export, and WebView process termination.

Web updates must verify signature/hash before activation, check the native runtime version, stage atomically, and retain one rollback copy. If an update needs a new native plugin, force a signed binary upgrade. Never silently fetch executable native code or hand catalog content a native bridge.

## Acceptance gates

Prototype acceptance is a physical-device run: fresh iPhone install through the actual signed path; first-run screen; offline launch; import a real video through PHPicker; proxy, timeline scrub, audio, export, and (if claimed) transcription; kill/relaunch during work; upgrade/reinstall while preserving projects; and visible, actionable failures for denial, no network, low storage, and expired signing. Verify the same with a real Android device for APK handoff, unknown-source consent, update with the same key, PackageInstaller conflict, and offline run.

App Store acceptance is separate: submit the exact host binary and catalog behavior for review, demonstrate the 4.7 safeguards, explain all remote content and permissions, and confirm that no 2.5.2-prohibited code-loading path exists. A successful local build, simulator run, TestFlight upload, mock PackageInstaller test, or source-level plugin is evidence of prototype progress only.

## Primary sources

Apple: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview/), [Choosing a Membership](https://developer.apple.com/support/compare-memberships/), [TestFlight](https://developer.apple.com/testflight/), [alternative distribution](https://developer.apple.com/documentation/marketplacekit/distributing-your-app-on-an-alternative-marketplace).  
Android: [PackageInstaller](https://developer.android.com/reference/android/content/pm/PackageInstaller), [install permission](https://developer.android.com/reference/android/Manifest.permission), [developer verification](https://developer.android.com/developer-verification/guides).  
Runtime references: [Capacitor](https://capacitorjs.com/docs), [Expo development builds](https://docs.expo.dev/develop/development-builds/faq/), [Expo runtime versions](https://docs.expo.dev/eas-update/runtime-versions/), [AltStore](https://github.com/altstoreio/AltStore), [PWABuilder](https://github.com/pwa-builder/PWABuilder).
