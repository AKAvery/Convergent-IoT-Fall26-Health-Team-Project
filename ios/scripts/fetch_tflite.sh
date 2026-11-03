#!/usr/bin/env bash
# Fetch the TensorFlow Lite C library that SoundRingKit's Detection module runs YAMNet with.
#
#   ios/scripts/fetch_tflite.sh      # once per checkout, before building the app (~80 MB download)
#
# Writes ios/Packages/SoundRingKit/Vendor/TensorFlowLiteC.xcframework (gitignored), which SoundRingKit/Package.swift uses
# as a binary target. It is Google's prebuilt TensorFlowLiteC 2.17.0, the library the
# TensorFlowLiteSwift CocoaPod wraps, repackaged as static libraries with a plain module map so it
# works with SwiftPM and no CocoaPods. iPhone and Simulator only: Google ships no macOS build, so on
# a Mac `swift test` skips the model tests (run them on a Simulator, see SoundRingKit/README.md).
set -euo pipefail

TFL_VERSION=2.17.0
URL="https://dl.google.com/tflite-release/ios/prod/tensorflow/lite/release/ios/release/32/20240729-115310/TensorFlowLiteC/2.17.0/0c10b3543e01f547/TensorFlowLiteC-2.17.0.tar.gz"
SHA256=9667b476015f136e5b332ce040e12822c4ac6d5c58947882ddc809cdff0fb99e

HERE="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$HERE/../Packages/SoundRingKit/Vendor"
WORK="$VENDOR/.work"
OUT="$VENDOR/TensorFlowLiteC.xcframework"

mkdir -p "$WORK"
cd "$WORK"

if [[ ! -f ios.tgz ]] || ! echo "$SHA256  ios.tgz" | shasum -a 256 -c --status; then
  echo "downloading TensorFlowLiteC $TFL_VERSION ..."
  curl -fSL -o ios.tgz "$URL"
fi
echo "$SHA256  ios.tgz" | shasum -a 256 -c --status || { echo "checksum mismatch for ios.tgz" >&2; exit 1; }
rm -rf ios && mkdir ios && tar xzf ios.tgz -C ios
SRC="ios/TensorFlowLiteC-$TFL_VERSION/Frameworks/TensorFlowLiteC.xcframework"

# Headers + a module map for a plain library. Google's umbrella header imports
# <TensorFlowLiteC/...> (framework style), so write our own with the C API we use.
rm -rf headers && mkdir headers
cp "$SRC/ios-arm64/TensorFlowLiteC.framework/Headers/"*.h headers/
rm headers/TensorFlowLiteC.h
cat > headers/TensorFlowLiteC.h <<'EOF'
#include "c_api.h"
#include "xnnpack_delegate.h"
EOF
cat > headers/module.modulemap <<'EOF'
module TensorFlowLiteC {
  umbrella header "TensorFlowLiteC.h"
  export *
  link "c++"
}
EOF

# Each framework binary is one prelinked object file; wrap it in a static archive.
mkdir -p libs/ios-arm64 libs/ios-sim
libtool -static -o libs/ios-arm64/libTensorFlowLiteC.a "$SRC/ios-arm64/TensorFlowLiteC.framework/TensorFlowLiteC"
libtool -static -o libs/ios-sim/libTensorFlowLiteC.a "$SRC/ios-arm64_x86_64-simulator/TensorFlowLiteC.framework/TensorFlowLiteC"

rm -rf "$OUT"
xcodebuild -create-xcframework \
  -library libs/ios-arm64/libTensorFlowLiteC.a -headers headers \
  -library libs/ios-sim/libTensorFlowLiteC.a -headers headers \
  -output "$OUT" >/dev/null
echo "-> $OUT"
