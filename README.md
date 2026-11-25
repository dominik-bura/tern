<p align="center"><img src="App/Assets/TernAppIcon-1024.png" width="144" alt="Tern icon"></p>
<h1 align="center">Tern</h1>
<p align="center"><strong>A home for every link.</strong></p>

Tern is a native macOS URL router with a standard menu-bar menu and a full configuration window. Send external links to the right browser or Dia profile, and switch profiles in your current Dia window. Built with SwiftUI and AppKit, using [Sift](https://github.com/dominik-bura/sift) as the application and delivery template.

## Highlights

- Ordered rules by domain and path, wildcard pattern, or regular expression, optionally limited to the app the link was clicked in (Slack, Mail, Teams, …), with a tester that never opens the link.
- Rule groups, drag-to-reorder, and per-rule usage counts.
- Redirect unwrapping (Outlook Safe Links, Google, Slack, Facebook, LinkedIn, Proofpoint, short links like t.co) and tracking-parameter removal before matching.
- Dia profile destinations and switching in your existing window.
- A destination picker for unmatched links and explicit browser destinations.
- Local, versioned rules with JSON import/export and separate development preferences.
- Clipboard opening on demand, default-browser setup and restoration, Open at Login, and a first-run welcome guide.
- Sift-style ZIP/DMG packaging and SHA-256-checked updates for production builds.

## Routing behavior

The first enabled rule wins. Hostnames match exactly or include subdomains at a domain boundary: `example.com` never matches `badexample.com`. Paths ignore case and match whole encoded segments: `/team` matches `/Team/docs`, but not `/teammate` or `/team%2Fdocs`. Wildcard patterns use `*` and are checked against the host only when they contain no `/` (`*.notion.so`), otherwise against host, path, and query (`*.atlassian.net/wiki/*`). Regular expressions are tested against the whole link, ignoring case. A rule can also require the app the link came from, which Tern reads from the sender of the open-URL event (falling back to the frontmost app); leave the domain empty to match every link from that app.

With **Unwrap Redirect Links** on (General), wrapped links are unwrapped locally before matching. Known short-link hosts are resolved with one cookieless `HEAD` request that doesn't follow the redirect. **Remove Tracking Parameters** strips `utm_*`, `fbclid`, `gclid`, and similar. Queries and fragments are forwarded unchanged. Use punycode for international hostnames.

Rules start empty. Tern never guesses which company owns a shared service. Configure a path rule for a GitHub organization or similar shared domain yourself. Unmatched links default to the browser that handled links before Tern; choose Ask Every Time or another fixed fallback in Rules.

Dia destinations use the profile's exact name, resolved in the frontmost window at delivery time. Missing or duplicate names fail visibly instead of opening in another account. Open Dia and refresh destinations after renaming profiles. A failed delivery stays in the queue until retried, redirected, or cancelled. A retry of an acknowledged tab creation focuses that tab instead of creating it again. If creation times out with an uncertain result, check Dia and cancel the request before trying the link again.

## Install and first launch

```sh
brew install --cask dominik-bura/tern/tern
```

Or download the DMG from [Releases](https://github.com/dominik-bura/tern/releases). Tern isn't notarized, so approve it once in System Settings → Privacy & Security on first launch.

To build from source instead:

1. Build and open `build/Tern Dev.app` using the commands below.
2. In **Browsers**, expand Dia and select **Refresh** with a Dia window open. Allow Tern to control Dia when macOS asks.
3. Add a rule, select a discovered Dia profile or browser, and test a URL in Rules.
4. Send a link directly to Tern, or deliberately choose **General → Make Default…** to route normal external links.

Production DMGs use the usual drag-to-Applications layout. An ad-hoc build is not Apple-notarized; macOS may require approval in Privacy & Security. Development and production builds have different identities and Automation consent.

## Requirements

macOS 14 or later. Dia is required for profile routing; other installed browsers work as browser-level destinations. See [local verification](docs/local-verification.md) for the versions and flows actually tested. If Dia has no window, Tern asks you to open one and retry before delivering the link.

## Using Tern

Open Tern's symbol in the menu bar for a standard macOS menu: **New Rule…**, **Open Link from Clipboard**, **Make Tern Default Browser…** (only while it isn't), and **Open Tern…**. A **Review Pending Link…** item appears when a delivery needs attention. **Open Tern…** brings up a resizable window with a native sidebar (Rules, Browsers, General), sidebar search, and back/forward navigation. Closing that window leaves Tern running in the menu bar. In **Rules**, add, edit, toggle, and reorder rules from each rule's ⋯ menu or context menu (double-click to edit), set where unmatched links open, and test a link. **Browsers** lists every installed browser. Browsers with profiles expand to show them, with the profile color or account picture, read from the browser's own files without launching it: Dia, Chromium browsers (Chrome, Edge, Brave, Vivaldi, Opera, Opera GX, Chromium, Thorium, Comet, Helium) via `Local State` and `--profile-directory`, and Firefox browsers (Firefox, Developer Edition, Nightly, Zen) via `profiles.ini` and `-P`. Chrome, Edge, and Firefox keep these files private on recent macOS; Tern then shows the detected profile folders and asks you to select the list file once (**Show Profile Names → Select File…**), which grants access to that one file, and remembers the names. Tern never asks for Full Disk Access. Safari, Arc, and Orion are browser-level only: they offer no way to open a link in a chosen profile. For Dia profiles you can also switch the frontmost window, or explicitly open its current page in another profile. Opening a page creates a new tab; it does not move the original.

The picker supports arrow-key selection, Return or double-click to open, Escape to cancel, Copy Link, Retry, and remembering an exact-host rule. Pending links are kept in arrival order. Closing the picker cancels the current link; any remaining link stays available.

General shows the actual HTTP/HTTPS handlers. **Make Default…** captures the prior handlers before requesting default-browser assignment; **Restore Previous…** restores them. Quitting does not change your default: macOS can relaunch Tern for the next link. Import replaces the rule configuration after validation; export writes it only to the location you choose. Corrupt or future-version files are preserved and block writes until repaired or moved aside.

## Compatibility and limits

Default-browser routing applies to links delivered through macOS. Ordinary in-browser clicks remain there. Universal Links, authentication sessions, and apps choosing a browser explicitly may bypass Tern. Profile targeting is Dia-specific; other browsers receive links at browser level. No browser extension, URL rewriting, redirect expansion, sync, or tab movement is included.

Tern creates a Dia tab directly inside the selected profile, then focuses it. Dia's own incoming Link Rules are separate; their interaction, full-screen/Spaces behavior, and closed-browser startup need the additional manual coverage listed in the test plan. Tern never changes Dia's settings.

## Privacy

No accounts, telemetry, URL logging, or persistent browsing history. Tern keeps only a count and last-used time per rule. Rules stay in the current app identity's Application Support directory. Pending URLs exist in memory and the deliberate picker UI. Clipboard access happens only when requested. Production update checks contact GitHub on launch, every six hours, and on demand. Development builds do not check for updates.

## Updates

Production builds check GitHub for newer versions and require an explicit installation action. Downloads require SHA-256 verification, a production bundle identity, a newer expected version, matching repository, a valid code signature, and a matching signing team when the installed app has one. The helper revalidates before replacing the bundle and restores the previous app if relaunch fails. Ad-hoc releases have weaker publisher identity than Developer ID builds. Updates wait until pending links are finished or cancelled.

## Build from source

```sh
git clone https://github.com/dominik-bura/tern.git
cd tern
swift test
./scripts/build-app.sh release
open "build/Tern Dev.app"
```

Swift tools 6.0+, Swift language mode 5, no third-party dependencies. `release` selects optimization; the channel remains development unless explicitly changed. Bundled builds support URL registration, artwork, and Automation consent. A bare executable is not the supported routing installation.

For a direct external-link test without changing system defaults:

```sh
open -a "$PWD/build/Tern Dev.app" 'https://example.com'
```

Generate artwork from the editable SVG masters in `assets/vector/` with `swift scripts/generate-icon-assets.swift`. Regeneration requires librsvg (`brew install librsvg`); regular app builds use the generated assets and need no extra renderer. See [releasing](docs/releasing.md), [manual testing](docs/manual-test-plan.md), and the [implementation specification](docs/implementation-plan.md).

## Contributing

[Open an issue](https://github.com/dominik-bura/tern/issues) with the macOS/Dia versions, window state, and expected routing behavior. Avoid including private URLs or tokens. Run the deterministic tests and bundle verification before proposing changes. Live browser tests are opt-in and must use disposable tabs.
