#!/bin/zsh
# Builds a universal (Apple silicon + Intel) Glowbar.app into ./build.
#   --install   also copy it to ~/Applications
#   --zip       also write build/Glowbar-<version>.zip for a GitHub release
#   --notarize  notarize the app with Apple and staple the ticket before zipping (implies --zip)
#
# Signing is ad-hoc by default, which is enough to run it on your own Mac. For a release,
# set SIGN_IDENTITY to a "Developer ID Application: …" certificate in your keychain and,
# for --notarize, NOTARY_PROFILE to credentials saved with `xcrun notarytool store-credentials`.
set -euo pipefail

root="${0:A:h:h}"
app="$root/build/Glowbar.app"

install=false zip=false notarize=false
for flag in "$@"; do
  case "$flag" in
    --install) install=true ;;
    --zip) zip=true ;;
    --notarize) notarize=true zip=true ;;
    *)
      echo "Unknown option $flag" >&2
      exit 2
      ;;
  esac
done
if $notarize && [[ -z "${SIGN_IDENTITY:-}" || -z "${NOTARY_PROFILE:-}" ]]; then
  echo "--notarize needs SIGN_IDENTITY and NOTARY_PROFILE" >&2
  exit 2
fi

# Builds <product> once per architecture and merges the slices with lipo, printing the
# universal binary's path. `swift build --arch arm64 --arch x86_64` would need Xcode's
# build system; this also works with just the Command Line Tools.
universal() {
  local product=$1 slices=() arch
  for arch in arm64 x86_64; do
    local triple="$arch-apple-macosx14.0"
    swift build --package-path "$root" -c release --triple "$triple" --product "$product" >&2
    slices+=("$(swift build --package-path "$root" -c release --triple "$triple" --show-bin-path)/$product")
  done
  mkdir -p "$root/build/universal"
  lipo -create "${slices[@]}" -output "$root/build/universal/$product"
  echo "$root/build/universal/$product"
}

app_bin="$(universal GlowbarApp)"
cli_bin="$(universal glowbar)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# The app target is GlowbarApp so its binary doesn't collide with the glowbar CLI
# on case-insensitive file systems.
cp "$app_bin" "$app/Contents/MacOS/Glowbar"
cp "$cli_bin" "$app/Contents/Resources/glowbar"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"

# App icon from assets/icon.svg
work="$(mktemp -d)"
qlmanage -t -s 1024 -o "$work" "$root/assets/icon.svg" >/dev/null 2>&1
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$work/icon.svg.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$work/icon.svg.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$work"

# Developer ID signatures get the hardened runtime and a secure timestamp, which
# notarization requires. The CLI is signed on its own first, then the app around it.
identity="${SIGN_IDENTITY:--}"
sign=(codesign --force --sign "$identity")
[[ "$identity" != "-" ]] && sign+=(--options runtime --timestamp)
"${sign[@]}" --identifier io.github.kombuchelada.glowbar.cli "$app/Contents/Resources/glowbar"
"${sign[@]}" "$app"
codesign --verify --strict "$app"
echo "Built $app ($(lipo -archs "$app/Contents/MacOS/Glowbar"), signed with ${SIGN_IDENTITY:-an ad-hoc signature})"

if $zip; then
  version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
  archive="$root/build/Glowbar-$version.zip"
  rm -f "$archive"
  ditto -c -k --keepParent "$app" "$archive"
  if $notarize; then
    echo "Submitting to Apple for notarization (usually a few minutes)…"
    xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
    # Attach the ticket to the app so it opens offline too, then zip it again.
    xcrun stapler staple "$app"
    spctl --assess --type execute --verbose=2 "$app"
    rm -f "$archive"
    ditto -c -k --keepParent "$app" "$archive"
  fi
  echo "Wrote $archive"
  # Values for Casks/glowbar.rb in github.com/Kombuchelada/homebrew-tap,
  # after uploading this zip to the v$version release.
  echo "Cask: version \"$version\""
  echo "      sha256 \"$(shasum -a 256 "$archive" | cut -d' ' -f1)\""
fi

if $install; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Glowbar.app"
  cp -R "$app" "$HOME/Applications/"
  echo "Installed to $HOME/Applications/Glowbar.app"
fi
