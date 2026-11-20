#!/bin/zsh
# Wraps a built (ideally notarized) Glowbar.app in a signed installer package.
#
#   INSTALLER_IDENTITY="Developer ID Installer: …" [NOTARY_PROFILE=<profile>] \
#       ./scripts/make-pkg.sh <path to Glowbar.app> [output.pkg]
#
# The package installs the app into /Applications and opens it for the user at the screen
# (Resources/pkg/postinstall). It requires macOS 14 or later. With NOTARY_PROFILE set, the
# package is notarized and stapled. The output defaults to build/Glowbar-<version>.pkg.
set -euo pipefail

root="${0:A:h:h}"
app_src="${1:?usage: ./scripts/make-pkg.sh <Glowbar.app> [output.pkg]}"
identity="${INSTALLER_IDENTITY:?set INSTALLER_IDENTITY to a \"Developer ID Installer: …\" certificate}"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_src/Contents/Info.plist")"
out="${2:-$root/build/Glowbar-$version.pkg}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root" "$work/scripts" "$work/packages"
ditto "$app_src" "$work/root/Glowbar.app"
cp "$root/Resources/pkg/postinstall" "$work/scripts/postinstall"

# Installer "relocates" bundles by default: if a copy with the same bundle ID exists
# anywhere else (say, the build folder), it updates that copy instead of /Applications.
pkgbuild --analyze --root "$work/root" "$work/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$work/component.plist"

pkgbuild --root "$work/root" --component-plist "$work/component.plist" \
  --install-location /Applications --scripts "$work/scripts" \
  --identifier io.github.kombuchelada.glowbar.pkg --version "$version" \
  "$work/packages/Glowbar.pkg" >/dev/null

# Start from the distribution productbuild would generate, then add a title and the
# macOS minimum.
productbuild --synthesize --package "$work/packages/Glowbar.pkg" "$work/distribution.xml" >/dev/null
python3 - "$work/distribution.xml" <<'PY'
import re, sys
path = sys.argv[1]
xml = open(path).read()
extra = """    <title>Glowbar</title>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
    <domains enable_localSystem="true" enable_anywhere="false" enable_currentUserHome="false"/>
    <allowed-os-versions>
        <os-version min="14.0"/>
    </allowed-os-versions>"""
xml = re.sub(r'\s*<options [^>]*/>', '', xml)
xml, count = re.subn(r'<installer-gui-script minSpecVersion="\d+">',
                     lambda m: '<installer-gui-script minSpecVersion="2">\n' + extra, xml, count=1)
assert count == 1, xml
open(path, 'w').write(xml)
PY

mkdir -p "${out:h}"
rm -f "$out"
productbuild --distribution "$work/distribution.xml" --package-path "$work/packages" \
  --sign "$identity" --timestamp "$out" >/dev/null

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Submitting $out to Apple for notarization…"
  xcrun notarytool submit "$out" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$out"
  spctl --assess --type install --verbose=2 "$out"
fi
pkgutil --check-signature "$out" | sed -n '2p'
echo "Wrote $out"
echo "      sha256 $(shasum -a 256 "$out" | cut -d' ' -f1)"
