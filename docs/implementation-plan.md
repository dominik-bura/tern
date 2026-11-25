# Tern implementation plan

Date: November 24, 2026

Build Tern as a native macOS menu-bar URL router, using Sift's application composition, packaging, update mechanism, release workflow, and README structure as the template. The first release must route external links into the correct Dia profile and switch profiles in an existing Dia window. Browser selection and an explicit fallback picker complete the initial product.

This is the original implementation specification. The native application, local build/packaging, updater and workflows have since been implemented; see [local verification](local-verification.md) for observed coverage and remaining release gates. No public release has been published.

Visual revision requested during implementation: use Sift's coral accent, translucent glass cards and compact 460-point panel; remove the logo/hero from the opened UI; use a coral-gradient bird on a white application tile. This supersedes the original teal/ivory color direction below. A subsequent user revision separates the surfaces: a standard macOS menu with native rows for quick actions, and a proper resizable configuration window with a Rules/Destinations/Settings sidebar. The full configuration no longer lives in the menu-bar popover. The latest visual revision follows the supplied Raycast/macOS settings reference: neutral appearance-aware surfaces, compact grouped rows, native controls, a searchable 228-point sidebar and navigation history. This supersedes the earlier Sift glass-card and coral-control treatment for the configuration UI.

## 1. Repository and template baseline

The local project is at `/Users/dominikhait/Documents/Eigene_Projekte/tern`. Its Git origin is `https://github.com/dominik-bura/tern.git`, with an unborn `main` branch. The remote advertised no refs when linked. The product, executable, bundle names, and repository documentation will use **Tern**.

Sift's local template is `/Users/dominikhait/Documents/Eigene_Projekte/sift`, at commit `7638e6252fee5b09d2b84a76e1824e146505561e`. Its working tree was clean during inspection. Its local release workflow exactly matched the workflow fetched from GitHub, with Git blob SHA `ed5afc17a9b48b15b88d9365b97969179fc7048f`.

Use a source copy of the relevant template files into Tern's independent Git history. Keep Sift's repository untouched. Record this baseline in the implementation notes so future template comparisons are reproducible.

Interpret one-to-one alignment as matching Sift's reusable application and delivery structure. Replace storage-cleanup behavior with routing behavior. The explicit differences are Tern's URL handling, Automation entitlement, routing tests, and omission of Sift's historical DevSweep migration support.

## 2. Template mapping

| Sift source or convention | Tern counterpart | Treatment |
| --- | --- | --- |
| `Package.swift` | `Package.swift` | Preserve Swift tools 6.0, Swift language mode 5, macOS 14 minimum, no third-party runtime dependencies, app/updater/test targets. Rename targets to `Tern`, `TernUpdater`, and `TernTests`. |
| `Sources/Sift/SiftApp.swift` | `Sources/Tern/TernApp.swift` | Preserve SwiftUI entry point, shared observable model, `MenuBarExtra`, window-style popover. Add an AppKit delegate for incoming URLs. |
| `AppModel.swift` | `Sources/Tern/AppModel.swift` | Preserve model ownership and update state conventions. Replace scan/cleanup state with rules, destinations, queued requests, permission status, and routing errors. |
| `ContentView.swift` | `Sources/Tern/ContentView.swift` | Reuse the visual grammar, footer settings control, update badge, and settings/quit placement. Replace cleanup and memory screens with routing screens. |
| `SiftAssets.swift`, funnel artwork | `TernAssets.swift`, tern artwork | Preserve asset registration and 18-point template menu-bar image behavior. Replace every visual asset with Tern's identity. |
| `Sources/Sift/UpdateService.swift` | `Sources/Tern/UpdateService.swift` | Adapt GitHub update discovery, checksum verification, staging, bundle/version/signature validation, and installer launch. Remove legacy identity transitions. |
| `Sources/SiftUpdater/main.swift` | `Sources/TernUpdater/main.swift` | Adapt wait/replace/relaunch/rollback flow and restrict it to Tern's identity. |
| `SecureCommandRunner.swift` | Same utility name if needed | Reuse bounded process execution for updater extraction. Keep URLs out of shell-generated command strings; omit Docker/uv-specific environment policy. |
| `App/Info.plist` | `App/Info.plist` | Preserve menu-bar app and platform metadata. Add HTTP/HTTPS URL types and Apple Events purpose text. |
| `scripts/build-app.sh` | Same path | Preserve app bundling, metadata injection, build channels, universal build switch, helper bundling, and signing order. Add app entitlements when signing. |
| `scripts/create-dmg.sh` | Same path | Preserve compressed DMG with app and `/Applications` shortcut. Rename staging paths and volume label. |
| Icon-generation scripts and `App/Assets/IconComposer` | Same layout with Tern names | Preserve reproducible asset tooling; replace funnel geometry with the approved bird. |
| `.github/workflows/release.yml` | Same path | Preserve main-push/manual release, tests, universal build, signing modes, notarization, package checks, checksums, and GitHub publishing. |
| `scripts/create-legacy-update-app.sh`, DevSweep bundles | None | Sift migration history has no Tern counterpart. Do not publish DevSweep artifacts or accept Sift identities. |
| `.gitignore` | `.gitignore` | Carry over Sift ignores; add `dist/` for generated release artifacts. |
| `README.md` | `README.md` | Follow Sift's centered icon/title/tagline, highlights, installation, usage, behavior, privacy, build, and contribution sections. Write Tern-specific content. |
| Cleanup/scanning services and tests | Routing/browser services and tests | Replace the product-specific subsystem entirely. |

Sift has one release workflow and no separate PR workflow in the inspected baseline. Add a small `ci.yml` for pull-request build/test validation as an explicit improvement. Do not claim this already exists in Sift. There was no tracked LICENSE, SECURITY, or CONTRIBUTING file in the inspected file inventory; do not invent inherited policies or add a license without the owner's choice.

## 3. Target repository layout

```text
.github/workflows/
  ci.yml
  release.yml
.gitignore
Package.swift
README.md
App/
  Info.plist
  Tern.entitlements
  Assets/
    Tern.icns
    TernAppIcon-1024.png
    TernMark.svg
    TernMenuBarIconTemplate.png
    TernMenuBarIconTemplate@2x.png
    TernMenuBarIconTemplate@3x.png
    IconComposer/
Sources/
  Tern/
    TernApp.swift
    AppDelegate.swift
    AppModel.swift
    ContentView.swift
    SettingsView.swift
    RuleEditorView.swift
    DestinationPickerView.swift
    TernAssets.swift
    Models.swift
    RuleStore.swift
    RuleEngine.swift
    RoutingCoordinator.swift
    BrowserRegistry.swift
    BrowserOpener.swift
    DiaService.swift
    AppleEventClient.swift
    DefaultBrowserService.swift
    UpdateService.swift
    SecureCommandRunner.swift
  TernUpdater/
    main.swift
Tests/TernTests/
  RuleEngineTests.swift
  RuleStoreTests.swift
  RoutingCoordinatorTests.swift
  DiaServiceTests.swift
  DefaultBrowserTests.swift
  UpdateServiceTests.swift
  UpdaterTests.swift
scripts/
  build-app.sh
  create-dmg.sh
  generate-icon-assets.swift
  generate-icon-composer-layers.swift
  compare-tern-icons.swift
  verify-bundle.sh
docs/
  implementation-plan.md
  manual-test-plan.md
  releasing.md
assets/
  icon-concept.png
```

Keep Sift's flat app-source layout initially. Separate the routing logic through small types and injected protocols rather than adding a framework, workspace generator, package registry, or separate backend. Updater tests may require a small importable helper target or a process-based fixture harness; choose the smaller approach during the updater adaptation.

## 4. Application identities and build parity

| Setting | Development | Production |
| --- | --- | --- |
| App name | `Tern Dev.app` | `Tern.app` |
| Main executable | `Tern` | `Tern` |
| Bundle identifier | `com.dominikbura.tern.dev` | `com.dominikbura.tern` |
| Version | `0.0.0` | `0.1.${github.run_number}` |
| Build number | `1` | `${github.run_number}` |
| Update repository | Empty; updates unavailable | `dominik-bura/tern` |
| Preferences and application support | Separate development location | Separate production location |
| Signing | Ad-hoc by default | Developer ID when configured; otherwise explicitly unsigned release mode |

Rename all `SIFT_*` build variables to `TERN_*`: build channel, version, build number, update repository, universal build, and signing identity. Rename metadata keys to `TernBuildChannel`, `TernBuildReference`, and `TernUpdateRepository`. Preserve the commit reference and dirty-tree suffix.

Retain these developer commands:

```sh
swift test
./scripts/build-app.sh release
open "build/Tern Dev.app"
```

As with Sift, `release` here selects compiler optimization; the default build channel remains development. A production bundle requires explicit production environment variables. Bundle builds are the supported way to exercise URL registration, bundled artwork, and Automation consent; bare `swift run Tern` is only a limited development convenience.

Declare `http` and `https` under `CFBundleURLTypes`, preserve `LSUIElement`, and add `NSAppleEventsUsageDescription`. Sign the main app with `com.apple.security.automation.apple-events`; the updater does not need this capability. Keep direct GitHub distribution and Sift's hardened-runtime approach. These additions follow Apple's [URL reception API](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:)) and [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events).

## 5. Routing behavior and data model

Implement `IncomingURLRequest`, `RoutingRule`, `URLMatcher`, `BrowserDestination`, `DiaProfileReference`, and `RoutingDecision` as explicit value types. Destinations support a browser, a Dia profile, or Ask Every Time. Each rule has a UUID, name, enabled state, ordered position, match conditions, and destination.

Use a versioned Codable JSON rule store in the current app identity's Application Support directory, with atomic writes and validated import/export. Keep lightweight UI preferences in UserDefaults. Reject unsupported future schema versions without overwriting them. Corrupt files produce a recoverable error rather than silently dropping rules.

For version one, support exact hostname, hostname plus subdomains, and optional path-prefix matching. Conditions within one rule use AND; the first enabled matching rule wins. Host matching is case-insensitive and respects domain boundaries: `example.com` must not match `badexample.com`. Specify path case sensitivity and segment boundaries in tests. Use a normalized representation for matching while forwarding the original URL unchanged, including query and fragment.

Begin with user-created rules and a fallback picker. Discover `Promptic` and `statworx` as selectable Dia destinations; do not infer company ownership of shared SaaS URLs or install speculative domain mappings. Show the parsed hostname and matched rule in a local rule tester.

Routing sequence:

1. Receive URLs through the app delegate, including deliveries during startup.
2. Validate supported schemes and capture a consistent rules snapshot.
3. Enqueue each request in arrival order.
4. Match a rule or present the fallback picker.
5. Dispatch through the selected browser adapter.
6. Show a useful failure with Retry, Choose Another Destination, and Copy URL when needed.

Serialize Dia operations so rapid links cannot race profile focus. Snapshot request state before awaiting permission or picker input. Track request IDs to prevent a retry after a partial failure from creating an unintended duplicate tab. Do not globally deduplicate equal URLs: two deliberate clicks may be valid.

Browser delivery must identify an explicit app through NSWorkspace. Exclude both Tern identities from destinations to prevent a routing loop. Support ordinary installed browsers as browser-level destinations in the initial release; profile targeting is specifically Dia-first. Source-application rules, regexes, URL rewrites, tracking removal, redirect expansion, other browser profiles, and browser extensions are later work.

## 6. Dia adapter and existing windows

Use Dia's scripting dictionary, with a typed Apple Events boundary or a fixed parameterized script called with Apple Event arguments. URLs and profile names are data; never interpolate them into executable AppleScript or shell source. Run potentially blocking automation on a dedicated serialized executor with bounded timeouts, leaving SwiftUI responsive.

The installed Dia 1.58.1 exposes profiles under a window, profile focus, profile-specific tab creation, tab focus, and tab movement. Earlier live verification in this chat confirmed `Promptic` and `statworx`, profile switching in place, temporary blank-tab creation in the destination profile, the same window ID, and restoration of the original view. This is a feasibility result, not full application validation.

For each routed URL, choose the target window before changing focus. Default to Dia's frontmost existing window. Resolve the configured profile there, create the tab directly in that profile, then focus the created tab. Identify the selected window by its runtime ID throughout the request. Never use a generic open-URL call followed by a profile switch: that can create the tab in the wrong account context.

The current dictionary exposes profile names and indexes but no stable profile ID. Store an app-owned destination UUID plus the last-known exact name and optional index hint. Re-resolve on use. Never bind only by index; reordering must not change a destination's account. A missing, renamed, or ambiguous profile requires explicit reselection. Do not scrape cookies, login databases, or private profile files.

Provide two distinct explicit actions: Switch Current Dia Window to Profile, and Open Current Page in Profile. Treat Move Current Tab as a separate optional action only after verifying Dia's move behavior with authenticated pages and unsaved form state; do not silently move existing tabs during ordinary routing.

The first integration milestone must verify Dia closed, Dia running with no windows, multiple windows, minimized windows, full-screen windows, two macOS Spaces, duplicate profile names, denied permission, and concurrent deliveries. Derive a safe cold-start/window-creation path from actual behavior before implementation depends on it. If this API cannot reliably create a window, present a clear Open Dia/retry state rather than silently falling back to an arbitrary profile. Avoid opening the destination URL until the target profile is resolved.

Dia also has its own [incoming Link Rules](https://www.diabrowser.com/changelog/mac). Verify whether explicit profile tab creation bypasses those rules. Document precedence and provide a clear troubleshooting path without modifying Dia's settings automatically.

## 7. Interface and onboarding

Match Sift's native typography, spacing, compact rows, footer settings entry, update badge, and settings-based Quit action. Use the approved teal/ivory bird identity with restrained teal accents.

The main popover contains Rules and Destinations, an Add Rule action, current default-browser status, quick profile-switch actions, and Open URL from Clipboard. Read the clipboard only when the user invokes that action. A separate native picker window can remain visible while a request awaits a destination; it must support keyboard navigation, cancellation, and multiple queued links.

The rule editor includes enabled state, name, URL conditions, destination, reorder controls, and a Test URL field. A successful test explains which rule wins without opening the URL. The destination view lists installed browsers and live Dia profiles, with refresh and explicit missing-profile states.

Onboarding proceeds through destination setup, a small user-initiated routing test, and an explicit Make Tern Default Browser action. Detect the actual HTTP and HTTPS handler state after completion; do not assume success from a button click. Capture previous handlers before changing them and offer an explicit restore action. Closing Tern does not automatically change the user's browser settings. Explain that macOS can relaunch the default handler when another link is opened. Development builds never take over as default without a deliberate user action.

An optional user-controlled Open at Login preference can be added using the native system API. Routing must still work when Tern is launched on demand through a link. Keep permission failure and partial default-handler states visible and recoverable.

## 8. Privacy and scope

Process routing locally, with no accounts, telemetry, or persistent browsing history. Do not log full URLs, queries, tokens, or clipboard content. Optional transient diagnostics show request state and rule names; any URL display must be deliberately user-visible and remain in memory unless the user exports it.

Rules themselves may contain private domains and paths. Store them locally and make export explicit. Preserve incoming URLs rather than automatically stripping parameters, expanding links, or probing remote destinations. Production network activity is limited to the update mechanism and explicit user-opened destinations.

Default-browser handling covers links delivered through macOS. Normal links clicked inside Dia remain in Dia; they require a later browser extension for interception or an explicit Open in Tern action. Universal Links, authentication sessions, and apps that specify their own browser may bypass the default handler. Publish this boundary in the README and test actual originating apps rather than promising interception of all links.

## 9. Icon and asset production

Preserve `assets/icon-concept.png` as the approved concept. It is a presentation image with a title and multiple sizes, not a shipping app icon.

Create the standalone bird artwork and rounded-square icon, keeping the approved silhouette, deep teal tile, warm ivory mark, and subtle depth. Produce a 1024-pixel app master, `.icns`, transparent vector menu-bar mark, and 18/36/54-pixel template PNGs. Follow Sift's asset scripts and optional IconComposer layer organization. Validate small sizes, light/dark menu bars, Retina rendering, Finder, Dock, and About/settings. The assets must have no embedded presentation title or extra miniature icons.

## 10. Release workflow parity

Adapt Sift's `.github/workflows/release.yml` with these exact operating conventions:

1. Trigger on every push to `main`, plus manual `workflow_dispatch`. Keep `macos-26`, the inspected pinned checkout action, `contents: write`, and non-cancelling concurrency renamed to `tern-release`.
2. Determine signing mode using the same six secrets: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`.
3. With all credentials present, import Developer ID into a temporary keychain. With all absent, produce an explicitly unsigned/ad-hoc release. A partially configured credential set fails rather than downgrading silently. Verify Tern's repository configuration during implementation; Sift's configured secret values have not been inspected or transferred.
4. Run `swift test` and build production `Tern.app` with universal arm64/x86_64 binaries for both the app and updater. Inject version `0.1.${github.run_number}`, build number `${github.run_number}`, and repository `${github.repository}`.
5. Sign the updater, then sign the app with its Automation entitlement and hardened runtime. Verify both architecture slices and that app identity and entitlements match the selected channel.
6. In signed mode, notarize and staple the app before creating the ZIP used by the updater.
7. Package `Tern-VERSION.zip` and a compressed `Tern-VERSION.dmg` with an Applications shortcut. Sign, notarize, staple, and validate the DMG in signed mode.
8. Verify code-signature integrity for all architectures. In signed mode, also assess Gatekeeper acceptance of app and DMG.
9. Generate `.zip.sha256` and `.dmg.sha256` sidecars after final packaging. Publish tag `vVERSION`, autogenerated notes, the ZIP/DMG, and checksums, targeting the checked-out commit. Preserve Sift's rerun behavior for an existing release. Label unsigned releases explicitly.

Do not create Tern's publishing workflow in the first documentation-only commit and accidentally ship an empty application. Introduce it when the first functional app passes the release gate; the bootstrap can use CI only. Once enabled, main pushes, including documentation-only changes, follow Sift's release behavior. No additional tag-trigger release workflow is needed.

Document runner/toolchain selection and validate it on the first Tern run. Keep workflow action pins deliberate. Never copy secrets into source files or assume access granted to Sift is automatically granted to Tern. Add cleanup of temporary signing material as a small explicit addition.

## 11. In-app updates

Preserve Sift's user-facing update states, settings badge, launch check, six-hour periodic check, manual Check Now, explicit install action, and development-channel unavailable state.

Change all archive prefixes, app/helper names, repository keys, User-Agent strings, staging prefixes, and error copy to Tern. Accept only `Tern.app` with `com.dominikbura.tern`; never permit Sift/DevSweep identity transitions or updates into `Tern Dev.app`.

Retain GitHub release lookup, SHA-256 validation from release digest or sidecar, constrained download origins, version/repository identity checks, code-signature validity, and same-team checks when the installed app has a team identity. Preserve clear writable-location errors and a release-page fallback. Unsigned mode is a weaker trust mode and should be labeled consistently with the release assets.

The updater waits for the parent, preserves the installed bundle as a backup, replaces it, relaunches, and restores the previous bundle if installation fails. Revalidate the staged candidate in the updater immediately before replacement to close the gap between app-side validation and installation; adapt rather than blindly clone this boundary. Extract reusable verification logic or pass a constrained receipt as needed. Keep diagnostics recoverable after helper failure.

Before quitting for an update, finish active routing or offer to defer installation. Verify how links delivered while the app is being replaced behave. Test preservation of rules, default-handler registration, and Automation consent across a same-identity signed update. Do not promise consent stability for ad-hoc builds without testing it.

## 12. README and repository documentation

The initial README must identify Tern as planned and link this implementation plan. Replace that status only when the app is available. The eventual product README follows Sift's order and level of practical detail:

| Section | Required Tern content |
| --- | --- |
| Icon, title, tagline | Centered standalone app icon; Tern; native Mac URL routing into the right browser/profile. |
| Introduction and Highlights | External links, Dia profile rules, current-window switching, fallback picker, local processing, updates. |
| Routing behavior | Ordered matching, shared-domain path examples, unchanged URL delivery, missing-profile behavior, and rule testing. |
| Install and First launch | GitHub latest DMG, drag to Applications, open menu-bar app, Automation consent, explicit default-browser setup, unsigned-build guidance when applicable. |
| Requirements | macOS 14+ for Tern; separately state Dia's own requirements and the versions actually tested. |
| Using Tern | Add destination, add rule, choose fallback, test link, switch profile, open clipboard URL, import/export, restore default browser. |
| Compatibility and Limits | Dia profile support, browser-level destinations elsewhere, internal browser clicks, Universal Links, OAuth flows, and Dia Link Rules interaction. |
| Privacy | Local rules, no telemetry/history, deliberate clipboard access, update-network behavior. |
| Updates | Automatic checks, explicit installation, validation, development build limitations. |
| Build from source | Clone `dominik-bura/tern`; `swift test`; bundle-build and launch commands; dev/production distinction. |
| Contributing | Issues link and short guidance; distinguish verified behavior from planned capabilities. |

Add `docs/releasing.md` with the exact variables, secrets, artifacts, version rule, signing-mode behavior, rerun behavior, rollback instructions, and first-release checklist. Add `docs/manual-test-plan.md` for the integration matrix. If an AGENTS.md is added, keep it focused on actual build commands, identity boundaries, URL privacy, and release checks; it is a deliberate addition to the inspected Sift template.

## 13. Validation and release gates

Automated tests must verify consequential behavior rather than reproduce view implementations:

- Matching: hostname boundaries, subdomains, ports, path boundaries, encoding, case, query/fragment preservation, ordered rules, disabled rules, and fallback.
- Persistence: atomic save, corrupt files, migrations, unsupported versions, invalid imports, and destination references.
- Coordination: startup deliveries, FIFO processing, multiple picker requests, denied Automation, timeouts, partial success/retry, and no self-routing.
- Dia adapter: exact-name resolution, missing/duplicate/reordered profiles, window selection, parameter-safe URLs/names, and create-before-focus ordering through a fake event client.
- Updates: version comparisons, allowed repository/assets, checksum failure, wrong identity/version/team, malformed archives, unwritable installation, staged revalidation, rollback, and exclusion of the development identity.

CI runs deterministic tests without controlling a developer's real browser. Local opt-in integration checks use disposable tabs and restore the previous view. Do not run automated browser UI tests that alter real accounts in hosted CI.

The manual matrix covers current macOS and the minimum supported system where available; installed Dia 1.58.1 and any later release used at shipping; all startup/window states; two Spaces; profile rename/reorder; HTTP and HTTPS defaults; links from several actual apps; OAuth sign-in return flows; internal browser links; concurrent bursts; and conflict with Dia Link Rules. Record environmental coverage rather than claiming untested versions work.

Release acceptance requires a clean test run, successful universal app/helper build, valid metadata and entitlements, actual external-link routing into both profiles, in-place window switching, no accidental wrong-profile fallback, usable permission recovery, correct assets, installable ZIP/DMG, correct checksum sidecars, and an update/rollback rehearsal using disposable app copies. A signed release additionally requires notarization, stapling, and Gatekeeper acceptance. CI publication success does not replace the live routing or update checks.

## 14. Implementation sequence

| Milestone | Deliverable | Completion check |
| --- | --- | --- |
| 0. Repository setup | Local origin, preserved concept, planning README, this plan. | Remote URL verified; no implementation or release claims. |
| 1. Sift template shell | Renamed package/app/updater targets, menu-bar shell, identity separation, asset pipeline, build scripts, PR CI. | Tests and Dev bundle build; all Sift/DevSweep product references removed except provenance. |
| 2. Dia integration proof | Profile discovery, exact destination resolution, current-window switching, profile-specific URL creation, cold start, permission recovery. | Disposable live probes pass; resolve no-window and multi-window behavior before committing to the adapter contract. |
| 3. Routing engine | Versioned rule store, deterministic matching, queued deliveries, explicit browser opener, request-level error handling. | Meaningful unit tests plus real links through a manually selected Tern handler. |
| 4. Product interface | Rule editor/tester, destinations, picker, onboarding/default restore, settings, clipboard action, quick profile switching. | Complete first-launch-to-correct-profile flow; keyboard and accessibility review. |
| 5. Delivery parity | Adapted updater, production packaging, release workflow, signing modes, documentation, release assets. | Disposable update/rollback rehearsal and signed/unsigned build-path verification as credentials allow. |
| 6. First release | Functional main baseline, installation notes, published artifacts, live smoke record. | Terminal GitHub checks, downloaded DMG install, actual routing and update behavior verified. |

Keep these as small reviewable commits or PRs. Do not publish partial releases before milestone 5 is ready. After the first complete release, use Sift's continuous main-branch release convention.

Deferred features are browser extensions for in-page link handling, source-app rules after provenance reliability is verified, non-Dia browser profiles, global hotkeys/Shortcuts integration, advanced URL transformations, rule sync, and bulk movement of existing tabs. They do not block the initial URL/profile router.

## Source references

- [Sift template at the inspected commit](https://github.com/dominik-bura/sift/tree/7638e6252fee5b09d2b84a76e1824e146505561e).
- [Sift release workflow](https://github.com/dominik-bura/sift/blob/7638e6252fee5b09d2b84a76e1824e146505561e/.github/workflows/release.yml), [build script](https://github.com/dominik-bura/sift/blob/7638e6252fee5b09d2b84a76e1824e146505561e/scripts/build-app.sh), [updater service](https://github.com/dominik-bura/sift/blob/7638e6252fee5b09d2b84a76e1824e146505561e/Sources/Sift/UpdateService.swift), and [helper](https://github.com/dominik-bura/sift/blob/7638e6252fee5b09d2b84a76e1824e146505561e/Sources/SiftUpdater/main.swift).
- Dia scripting dictionary inspected locally at `/Applications/Dia.app/Contents/Resources/Dia.sdef`; live feasibility checks are recorded in this chat.
- [Apple URL delivery](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:)), [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace), and [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events).
- [Tern repository](https://github.com/dominik-bura/tern).
