#!/bin/sh
set -eu

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PRODUCTS_DIR="${SHUTTLE_PRODUCTS_DIR:-$PROJECT_DIR/products/Release}"
DERIVED_DATA_PATH="${SHUTTLE_DERIVED_DATA_PATH:-$PROJECT_DIR/.deriveddata}"
ARCH="${SHUTTLE_ARCH:-$(uname -m)}"
DESTINATION="${SHUTTLE_DESTINATION:-platform=macOS,arch=$ARCH,name=My Mac}"

mkdir -p "$PRODUCTS_DIR"

xcodebuild \
  -project "$PROJECT_DIR/Shuttle.xcodeproj" \
  -scheme Shuttle \
  -configuration Release \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CONFIGURATION_BUILD_DIR="$PRODUCTS_DIR" \
  build
