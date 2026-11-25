#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
product_dir="$repo_dir/build"
build_channel="${TERN_BUILD_CHANNEL:-development}"
codesign_identity="${TERN_CODESIGN_IDENTITY:--}"
build_reference="$(git -C "$repo_dir" rev-parse --short=8 HEAD 2>/dev/null || printf 'unknown')"
if [[ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]]; then
    build_reference="${build_reference}-dirty"
fi

case "$build_channel" in
    development)
        app_name="Tern Dev"
        bundle_identifier="com.dominikbura.tern.dev"
        app_dir="$product_dir/Tern Dev.app"
        version="0.0.0"
        build_number="1"
        update_repository=""
        ;;
    production)
        app_name="Tern"
        bundle_identifier="com.dominikbura.tern"
        app_dir="$product_dir/Tern.app"
        version="${TERN_VERSION:-}"
        build_number="${TERN_BUILD_NUMBER:-}"
        update_repository="${TERN_UPDATE_REPOSITORY:-}"
        if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
            echo "Production builds require TERN_VERSION in x.y.z form" >&2
            exit 64
        fi
        if [[ ! "$build_number" =~ '^[1-9][0-9]*$' ]]; then
            echo "Production builds require a positive TERN_BUILD_NUMBER" >&2
            exit 64
        fi
        if [[ ! "$update_repository" =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ]]; then
            echo "Production builds require TERN_UPDATE_REPOSITORY as owner/repository" >&2
            exit 64
        fi
        ;;
    *)
        echo "TERN_BUILD_CHANNEL must be development or production" >&2
        exit 64
        ;;
esac

cd "$repo_dir"
mkdir -p "$repo_dir/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$repo_dir/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_dir/.build/module-cache"
build_arguments=(-c "$configuration" --disable-sandbox)
if [[ "${TERN_UNIVERSAL:-0}" == "1" ]]; then
    build_arguments+=(--arch arm64 --arch x86_64)
fi
swift build "${build_arguments[@]}"

binary_dir="$(swift build "${build_arguments[@]}" --show-bin-path)"
binary_path="$binary_dir/Tern"
updater_path="$binary_dir/TernUpdater"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Helpers"
cp "$binary_path" "$app_dir/Contents/MacOS/Tern"
# SwiftPM records the deployment target as the linked SDK version. AppKit uses that value to
# decide whether to adopt the current system design (Liquid Glass on macOS 26+), so stamp the
# SDK the binary was actually built with.
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
minimum_version="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$repo_dir/App/Info.plist")"
vtool -set-build-version macos "$minimum_version" "$sdk_version" -replace \
    -output "$app_dir/Contents/MacOS/Tern" "$app_dir/Contents/MacOS/Tern" 2> >(grep -v "code signature will be invalid" >&2)
cp "$updater_path" "$app_dir/Contents/Helpers/TernUpdater"
cp "$repo_dir/App/Info.plist" "$app_dir/Contents/Info.plist"
cp "$repo_dir/App/Assets/Tern.icns" "$app_dir/Contents/Resources/Tern.icns"
cp "$repo_dir/App/Assets/TernAppIcon-1024.png" "$app_dir/Contents/Resources/TernAppIcon-1024.png"
cp "$repo_dir/App/Assets/TernAppIcon.svg" "$app_dir/Contents/Resources/TernAppIcon.svg"
cp "$repo_dir/App/Assets/TernLogo.svg" "$app_dir/Contents/Resources/TernLogo.svg"
cp "$repo_dir/App/Assets/TernLogoMonochrome.svg" "$app_dir/Contents/Resources/TernLogoMonochrome.svg"
cp "$repo_dir/App/Assets/TernMark.svg" "$app_dir/Contents/Resources/TernMark.svg"
cp "$repo_dir/App/Assets/TernMenuBarIconTemplate.png" "$app_dir/Contents/Resources/TernMenuBarIconTemplate.png"
cp "$repo_dir/App/Assets/TernMenuBarIconTemplate@2x.png" "$app_dir/Contents/Resources/TernMenuBarIconTemplate@2x.png"
cp "$repo_dir/App/Assets/TernMenuBarIconTemplate@3x.png" "$app_dir/Contents/Resources/TernMenuBarIconTemplate@3x.png"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $app_name" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_identifier" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :TernUpdateRepository $update_repository" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :TernBuildChannel string $build_channel" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :TernBuildReference string $build_reference" "$app_dir/Contents/Info.plist"
codesign --force --options runtime --sign "$codesign_identity" "$app_dir/Contents/Helpers/TernUpdater"
codesign --force --options runtime --entitlements "$repo_dir/App/Tern.entitlements" --sign "$codesign_identity" "$app_dir"

echo "$app_dir"
