#!/bin/zsh
set -euo pipefail
app="${1:?Usage: verify-bundle.sh /path/to/Tern.app [universal]}"
plist="$app/Contents/Info.plist"
channel=$(/usr/libexec/PlistBuddy -c 'Print :TernBuildChannel' "$plist")
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
if [[ "$channel" == production ]]; then
    [[ "$identifier" == com.dominikbura.tern && "${app:t}" == Tern.app ]]
else
    [[ "$identifier" == com.dominikbura.tern.dev && "${app:t}" == 'Tern Dev.app' ]]
    [[ -z "$(/usr/libexec/PlistBuddy -c 'Print :TernUpdateRepository' "$plist")" ]]
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$plist")" == true ]]
[[ -n "$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$plist")" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$plist")" == http ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:1' "$plist")" == https ]]
for binary in "$app/Contents/MacOS/Tern" "$app/Contents/Helpers/TernUpdater"; do
    [[ -x "$binary" ]]
    if [[ "${2:-}" == universal ]]; then
        /usr/bin/lipo -verify_arch arm64 "$binary"
        /usr/bin/lipo -verify_arch x86_64 "$binary"
    fi
done
codesign --verify --deep --strict --all-architectures "$app"
entitlements=$(mktemp)
trap 'rm -f "$entitlements"' EXIT
codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.automation.apple-events' "$entitlements")" == true ]]
echo "Verified $channel bundle, URL handlers, Automation entitlement, helper, and signatures."
