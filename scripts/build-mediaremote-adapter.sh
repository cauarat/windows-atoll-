#!/bin/sh
# Builds MediaRemoteAdapter.framework from the vendored BSD-3 source.
#
# Why this exists rather than a prebuilt binary: Notchy is GPL v3, and GPL v3
# §6 obliges us to offer Corresponding Source for everything we distribute.
# Shipping an opaque framework we cannot build would breach that. It is also
# the only way the framework gets signed with our Developer ID -- a prebuilt
# ad-hoc binary fails notarization.
#
# Reading now-playing info has been gated to entitled processes since macOS
# 15.4. The workaround is upstream's: the read happens inside Apple-signed
# /usr/bin/perl, which DynaLoads this framework. Sending commands needs no
# adapter and goes straight to the private MediaRemote framework.
#
# clang directly rather than CMake: the build is 15 .m files and three system
# frameworks, and not requiring CMake keeps the toolchain to Xcode alone.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/third_party/mediaremote-adapter"
OUT="${1:-$ROOT/NotchBuddy/Frameworks}"
FW="$OUT/MediaRemoteAdapter.framework"

if [ ! -d "$SRC/src" ]; then
    echo "error: vendored source missing at $SRC" >&2
    exit 1
fi

rm -rf "$FW"
mkdir -p "$FW/Versions/A/Headers" "$FW/Versions/A/Resources"

# -fvisibility=default is required, not cosmetic: the Perl script resolves the
# exported functions by name, and hidden symbols make it silently unusable.
clang -dynamiclib -fobjc-arc -fvisibility=default \
    -arch x86_64 -arch arm64 \
    -I"$SRC/include" -I"$SRC/src" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
    -o "$FW/Versions/A/MediaRemoteAdapter" \
    "$SRC"/src/adapter/*.m "$SRC"/src/private/*.m "$SRC"/src/utility/*.m

cp "$SRC/include/MediaRemoteAdapter.h" "$FW/Versions/A/Headers/"

cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
  <key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
  <key>CFBundleName</key><string>MediaRemoteAdapter</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
PLIST

# Versioned-bundle symlinks. macOS frameworks are looked up through these.
ln -s A "$FW/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -s Versions/Current/Headers "$FW/Headers"
ln -s Versions/Current/Resources "$FW/Resources"

# No signing here. Xcode signs it on embed with the app's identity, which is
# what notarization requires; ad-hoc signing it now would only get replaced.

echo "built $(lipo -archs "$FW/Versions/A/MediaRemoteAdapter") -> $FW"
