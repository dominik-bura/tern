#!/usr/bin/env bash
# Writes a Homebrew cask for a published release.
# Usage: scripts/generate-cask.sh VERSION DMG_SHA256 OWNER/REPO [unsigned] > tern.rb
# "unsigned" adds a postflight step that clears the quarantine flag, since Gatekeeper
# blocks apps that aren't notarized.
set -euo pipefail

version="${1:?version}"
sha256="${2:?sha256 of the DMG}"
repository="${3:?owner/repo}"
signing="${4:-signed}"

[[ "${version}" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Invalid version: ${version}" >&2; exit 1; }
[[ "${sha256}" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid SHA-256: ${sha256}" >&2; exit 1; }
[[ "${repository}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid repository: ${repository}" >&2; exit 1; }

cat <<CASK
cask "tern" do
  version "${version}"
  sha256 "${sha256}"

  url "https://github.com/${repository}/releases/download/v#{version}/Tern-#{version}.dmg"
  name "Tern"
  desc "Opens each link in the right browser and profile"
  homepage "https://github.com/${repository}"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Tern.app"
CASK

if [[ "${signing}" == "unsigned" ]]; then
cat <<'CASK'

  # Tern is not notarized. Clearing quarantine lets it open without a Gatekeeper prompt.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Tern.app"]
  end
CASK
fi

cat <<CASK

  uninstall quit: "com.dominikbura.tern"

  zap trash: [
    "~/Library/Application Support/com.dominikbura.tern",
    "~/Library/Preferences/com.dominikbura.tern.plist",
  ]
end
CASK
