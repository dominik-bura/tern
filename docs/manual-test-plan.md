# Manual test plan

Record exact versions and observed coverage in `local-verification.md`. Use disposable URLs/tabs and restore the original Dia profile/tab. Never print private tab URLs into logs.

## Local acceptance

- Build/test; verify production and development identities, signatures, resources, and URL/Automation metadata.
- Launch the bundle: native menu-bar rows and profile submenu; Open Tern opens a resizable configuration window with General, Rules and Browsers & Profiles in its searchable sidebar. Check sidebar search and clearing it, toolbar Back/Forward history, the native grouped rule editor, standard close/minimize/zoom controls, window resizing, closing and reopening through the menu, rule editor/tester, native keyboard focus and Escape. Closing configuration must keep the router running.
- Refresh installed browsers and Dia profiles, handle consent and denial, recover from missing/renamed/duplicate profiles without opening in another account.
- Create two exact-host/path rules targeting different profiles. Open links via macOS explicitly in Tern, verify the created tab's URL/profile, and confirm the same Dia window ID.
- Open unmatched links, choose a destination, remember hostname, cancel, copy a URL, and test multiple queued links including repeated URLs.
- Toggle/reorder rules and relaunch to check persistence. Export/import a valid configuration; invalid/corrupt/future schema must not overwrite original data.
- Switch profiles without opening tabs. Open Current Page creates a new tab in the chosen profile without moving the original.
- Deliberately make Tern the default, verify HTTP and HTTPS separately, then restore both prior handlers. Do not change defaults just to run unrelated checks.
- Package ZIP and DMG; verify checksums, mount read-only, confirm Applications shortcut and signatures. Run opt-in updater replacement/rollback/tamper tests.

## Extended compatibility matrix

Test Dia closed; running without windows; multiple windows; minimized and full-screen windows; separate macOS Spaces; slow startup; profile rename/reorder; duplicate names; denied Automation; timeouts before and after tab creation; simultaneous links; closing a picker with more links queued. No-window handling must ask to open a window and retry before opening any target URL.

Check incoming links from several real originating apps, HTTP and HTTPS, query/fragment preservation, authentication callbacks, Universal Links and internal browser clicks. Check explicit profile creation against conflicting Dia Link Rules without modifying user rules automatically.

Check current and minimum macOS versions where available, light/dark menu bars, Retina icons, VoiceOver labels and keyboard-only operation. A supported deployment target is not evidence of testing every OS version.

Signed release acceptance additionally requires notarization, stapling, Gatekeeper, a downloaded installation and a real signed update preserving rules, handler registration and Automation consent. Ad-hoc consent persistence across rebuilding is not guaranteed.
