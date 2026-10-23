#!/bin/zsh
# Builds a universal (Apple silicon + Intel) Glowbar.app into ./build.
#   --install  also copy it to ~/Applications
#   --zip      also write build/Glowbar-<version>.zip for a GitHub release
set -euo pipefail

root="${0:A:h:h}"
app="$root/build/Glowbar.app"
arch_flags=(--arch arm64 --arch x86_64)

swift build --package-path "$root" -c release "${arch_flags[@]}" --product GlowbarApp
swift build --package-path "$root" -c release "${arch_flags[@]}" --product glowbar
bin="$(swift build --package-path "$root" -c release "${arch_flags[@]}" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# The app target is GlowbarApp so its binary doesn't collide with the glowbar CLI
# on case-insensitive file systems.
cp "$bin/GlowbarApp" "$app/Contents/MacOS/Glowbar"
cp "$bin/glowbar" "$app/Contents/Resources/glowbar"
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

# Ad-hoc signature: enough to run locally; not notarized.
codesign --force --sign - "$app/Contents/Resources/glowbar"
codesign --force --sign - "$app"
echo "Built $app ($(lipo -archs "$app/Contents/MacOS/Glowbar"))"

for flag in "$@"; do
  case "$flag" in
    --install)
      mkdir -p "$HOME/Applications"
      rm -rf "$HOME/Applications/Glowbar.app"
      cp -R "$app" "$HOME/Applications/"
      echo "Installed to $HOME/Applications/Glowbar.app"
      ;;
    --zip)
      version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
      zip="$root/build/Glowbar-$version.zip"
      rm -f "$zip"
      ditto -c -k --keepParent "$app" "$zip"
      echo "Wrote $zip"
      # Values for Casks/glowbar.rb in github.com/Kombuchelada/homebrew-tap,
      # after uploading this zip to the v$version release.
      echo "Cask: version \"$version\""
      echo "      sha256 \"$(shasum -a 256 "$zip" | cut -d' ' -f1)\""
      ;;
    *)
      echo "Unknown option $flag" >&2
      exit 2
      ;;
  esac
done
