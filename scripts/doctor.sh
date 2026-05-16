#!/usr/bin/env bash
set -euo pipefail

missing=0

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing: $1" >&2
    missing=1
  fi
}

require xcodebuild
require xcode-select
require xcrun
require swift
require xcodegen

if [ "$missing" -ne 0 ]; then
  echo "Install Xcode 26+, Xcode command line tools, and XcodeGen." >&2
  exit 1
fi

xcode_version="$(xcodebuild -version | awk '/^Xcode / { print $2; exit }')"
swift_version="$(swift --version | sed -n 's/.*Swift version \([0-9][0-9.]*\).*/\1/p' | head -n 1)"
macos_sdk="$(xcrun --sdk macosx --show-sdk-version)"
developer_dir="$(xcode-select -p)"

xcode_major="${xcode_version%%.*}"
swift_major="${swift_version%%.*}"

if [ -z "$xcode_major" ] || [ "$xcode_major" -lt 26 ]; then
  echo "Xcode 26 or newer is required; found Xcode ${xcode_version:-unknown}." >&2
  exit 1
fi

if [ -z "$swift_major" ] || [ "$swift_major" -lt 6 ]; then
  echo "Swift 6 compiler or newer is required; found Swift ${swift_version:-unknown}." >&2
  exit 1
fi

echo "Xcode: $xcode_version"
echo "Swift compiler: $swift_version"
echo "macOS SDK: $macos_sdk"
echo "Developer dir: $developer_dir"
