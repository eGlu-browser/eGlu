#!/bin/zsh
# Builds EgluEngines.xcframework: the eglu-engines static library for
# macOS (arm64 + x86_64), iOS device, and the iOS simulator (arm64 + x86_64),
# then zips it as EgluEngines.xcframework.zip and prints its checksum for
# Package.swift.

set -euo pipefail
cd "$(dirname "$0")"

export MACOSX_DEPLOYMENT_TARGET=26.0
export IPHONEOS_DEPLOYMENT_TARGET=17.0

TARGETS=(aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)

rm -rf build
mkdir -p build

for target in $TARGETS; do
    cargo build --release --target "$target" -p eglu-engines
done

mkdir -p build/macos build/iossim
lipo -create \
    target/aarch64-apple-darwin/release/libeglu_engines.a \
    target/x86_64-apple-darwin/release/libeglu_engines.a \
    -output build/macos/libeglu_engines.a
lipo -create \
    target/aarch64-apple-ios-sim/release/libeglu_engines.a \
    target/x86_64-apple-ios/release/libeglu_engines.a \
    -output build/iossim/libeglu_engines.a

xcodebuild -create-xcframework \
    -library build/macos/libeglu_engines.a -headers include \
    -library target/aarch64-apple-ios/release/libeglu_engines.a -headers include \
    -library build/iossim/libeglu_engines.a -headers include \
    -output build/EgluEngines.xcframework

ditto -c -k --keepParent build/EgluEngines.xcframework build/EgluEngines.xcframework.zip

echo "Slice sizes:"
for target in $TARGETS; do
    printf "  %-28s %s\n" "$target" "$(du -h target/$target/release/libeglu_engines.a | cut -f1)"
done
printf "  %-28s %s\n" "EgluEngines.xcframework.zip" "$(du -h build/EgluEngines.xcframework.zip | cut -f1)"

echo "Checksum:"
swift package compute-checksum build/EgluEngines.xcframework.zip
