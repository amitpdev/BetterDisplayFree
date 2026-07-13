# Create a compressed DMG from a notarized .app and verify the result.
#
# Usage:
#   just dmg BetterDisplayFree.app
dmg app_path:
    #!/usr/bin/env bash
    set -euo pipefail

    app_path="{{app_path}}"
    if [[ ! -d "$app_path" || "${app_path##*.}" != "app" ]]; then
      echo "Expected a .app directory, got: $app_path" >&2
      exit 1
    fi

    app_abs="$(cd "$(dirname "$app_path")" && pwd)/$(basename "$app_path")"
    app_name="$(basename "$app_abs" .app)"
    dmg_path="$(pwd)/${app_name}.dmg"
    mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/${app_name}.dmg.XXXXXX")"

    cleanup() {
      hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true
      rmdir "$mount_dir" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    echo "Verifying app: $app_abs"
    codesign --verify --deep --strict --verbose=2 "$app_abs"
    xcrun stapler validate "$app_abs"
    spctl --assess --type execute --verbose "$app_abs"

    echo "Creating DMG: $dmg_path"
    hdiutil create \
      -volname "$app_name" \
      -srcfolder "$app_abs" \
      -ov \
      -format UDZO \
      "$dmg_path"

    echo "Verifying DMG structure"
    hdiutil verify "$dmg_path"

    echo "Verifying app from mounted DMG"
    hdiutil attach "$dmg_path" -nobrowse -readonly -mountpoint "$mount_dir" -quiet
    mounted_app="$mount_dir/$(basename "$app_abs")"
    codesign --verify --deep --strict --verbose=2 "$mounted_app"
    xcrun stapler validate "$mounted_app"
    spctl --assess --type execute --verbose "$mounted_app"

    echo "Checksum:"
    shasum -a 256 "$dmg_path"
