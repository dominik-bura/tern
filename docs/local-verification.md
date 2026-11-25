# Local verification — November 24, 2026

Tern is implemented and built locally using Sift at `7638e6252fee5b09d2b84a76e1824e146505561e` as the template. Sift's source was not changed. Nothing has been committed, pushed, or published by this implementation session.

## Visual alignment

The menu bar uses the standard macOS menu style: native rows for routing status, Open Tern, Settings, clipboard opening, a Switch Dia Profile submenu, and Quit. There is no custom menu-bar panel.

Configuration lives in a separate native resizable window with standard title-bar controls and a searchable sidebar for General, Rules, and Browsers & Profiles. The shared app model owns configuration and routing independently of this window. Opening it gives Tern normal Dock/Command-Tab presence; closing it returns Tern to its menu-bar role. The same window and selected page are reused when reopened, and its frame is saved. Settings is a full page rather than an overlay.

The configuration window now follows the supplied Raycast/macOS settings reference: a 228-point dark sidebar, search field, neutral selection, small icon tiles, native navigation toolbar, compact section labels and grouped rows with trailing controls. The main surface and groups use opaque, appearance-aware colors rather than glass/refraction or raised cards. Controls use the system accent. General, Rules and Browsers & Profiles all share these proportions and typography; the rule editor uses a native grouped Form. The application icon is the selected pair of bright orange cardboard-textured folded planes on a white tile. Its editable SVG masters live in `assets/vector/`; it is not shown as a large window heading.

## Verified

- Optimized development bundle: `build/Tern Dev.app`, `com.dominikbura.tern.dev`, updates disabled.
- Production bundle: `build/Tern.app`, version 0.1.1, `com.dominikbura.tern`, ad-hoc signed.
- Universal production app and updater: arm64 and x86_64 slices. Both binaries carry a macOS 14 deployment minimum.
- URL scheme registration, menu-bar metadata, Automation purpose/entitlement, embedded helper, and code-signature integrity.
- 23 automated tests passed with the production fixture and real ZIP enabled, with no skips: routing/matching/store tests, FIFO failure/retry/explicit redirect, default-handler state, parameter-safe adapter calls, update identity/archive/checksum checks, and three disposable replacement/rollback/tamper rehearsals.
- Actual built-app Dia discovery found `Promptic` and `statworx` in Dia 1.58.1.
- Tern's Switch action changed the existing Dia window to statworx without creating a new window.
- A rule created through Tern's editor delivered `https://example.com/tern-promptic?test=a%2Bb#Tern` into Promptic, preserving the exact URL and existing window ID.
- A two-link burst through a statworx rule created each expected URL exactly once in statworx, reused the same window, and focused the last queued tab.
- The rule tester showed the expected Promptic rule without opening a link.
- An unmatched link presented the native picker; choosing Promptic completed delivery.
- Production ZIP integrity, updater archive validation, DMG read-only mount, packaged signature/architectures, Applications shortcut and checksum sidecars.

The update rehearsal replaces only disposable application copies and injects a launcher. It exercises the real shared validation/installation code but does not claim a real GitHub download or signed in-place update was performed.

## Coverage still requiring deliberate manual checks

System default-browser assignment/restoration was not invoked; links were delivered explicitly through macOS `open -a` to preserve the user's existing defaults. The service and actual HTTP/HTTPS status UI are implemented.

Dia closed/no-window startup, multiple windows/Spaces/full-screen/minimized cases, profile rename/duplicates, a fresh denied Automation prompt, conflicting Dia Link Rules, actual OAuth return flows, and minimum-OS runtime coverage remain in the manual matrix. The no-window path fails visibly before opening a target URL and asks the user to open a window and retry.

No Developer ID signing credentials were configured or transferred. Notarization, stapling, Gatekeeper distribution acceptance, remote CI/release execution, downloaded installation, and a real same-identity signed update remain release gates. Local artifacts are ad-hoc signed.

## Current local state

The development app was rebuilt and launched with the reference-style settings design. General, Rules, Browsers & Profiles and the native grouped rule editor were visually inspected. Sidebar search for `update` selected General and filtered navigation correctly; clearing it restored the sections. Toolbar Back and Forward navigated between General and Rules with the expected enabled/disabled states. Escape dismissed the rule editor without saving. Refresh discovered both Promptic and statworx. The app was left open on General. The native menu-bar implementation remains unchanged.

An earlier window-layout check verified native zoom and restoring the previous size. The regression suite includes 23 routing/persistence/coordination/updater tests; this design pass also refreshes the local production artifacts.

The desktop automation timed out while inspecting SystemUIServer for the separate menu-bar item. The menu is implemented with SwiftUI's built-in `.menuBarExtraStyle(.menu)` and native menu rows; this inspection did not change routing configuration or browser defaults. Background routing after closing the new configuration window still needs an additional live smoke check; the shared routing model remains owned by the app, and the close handler does not terminate it.

Earlier live-test rules and disposable tabs were removed, and Dia's original profile/tab was restored. User rules and browser defaults were not modified by this window/menu rework. Local artifacts are in `dist/Tern-0.1.1.zip` and `dist/Tern-0.1.1.dmg` with SHA-256 sidecars; they are not published releases. Runtime integration used macOS 27.2 (26B123); the macOS 14 binary deployment target was verified but not exercised on an older Mac.

## Earlier settings readability correction

Before the separate configuration window was introduced, the clear-glass settings overlay let destination labels/icons show through its controls. An opaque backing fixed that issue. The new Settings page removes the overlay entirely and uses an opaque window background behind its cards.

## Orange cardboard identity — November 25

The selected production artwork is `assets/vector/iterations/orange-cardboard-white-larger/tern-cardboard-white-larger.svg`: a white tile, bright orange folded planes, stronger matte cardboard fibers and grain, and the slightly larger mark (placement scale 1.15). This replaces the dark silver treatment. The geometry retains the slimmer bands, tighter spacing, and 13-unit overlap clearance; the tile remains the standard 824×824 opaque footprint at (100,100)–(924,924) on its 1024 canvas.

The canonical app-icon master is `assets/vector/tern-switch-icon.svg`; the historical filename is retained for the existing pipeline. `assets/vector/tern-fold-logo.svg` exports the standalone orange logo with the same vector fibers, pigment pits, surface filter, gradients and cutouts. Neither SVG embeds a raster image. The monochrome logo and simplified native menu-bar symbol retain the approved geometry; decorative texture and orange color are reserved for the full logo and app icon.

The generator renders the master with librsvg to preserve the SVG texture and masks, then produces all ten app-icon sizes and `.icns`, app SVG/PNG, standalone shaded and monochrome SVGs, and 1×/2×/3× native menu-bar templates. `TernAssets` assembles the PNG menu representations into one native template image because CoreSVG does not preserve luminance-mask cutouts. The build script bundles all generated assets, and the development app refreshes its application icon on launch.

Development and universal production bundles, helper signatures, native icon dimensions, texture/selected-master parity, unchanged monochrome menu assets, and local ZIP/DMG checksums are verified after rebuilding. No routing behavior changes are part of the identity update.
