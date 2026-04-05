#!/bin/sh
set -eu

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PRODUCTS_DIR="$PROJECT_DIR/products/Debug"

mkdir -p "$PRODUCTS_DIR"

xcodebuild \
  -project "$PROJECT_DIR/Shuttle.xcodeproj" \
  -scheme Shuttle \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64,name=My Mac" \
  -derivedDataPath "$PROJECT_DIR/.deriveddata" \
  CONFIGURATION_BUILD_DIR="$PRODUCTS_DIR" \
  build
