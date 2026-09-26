#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/codexlimits-checks.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
bundle="$build_dir/PresentationChecks.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.buildsucceeded.codex-limits.presentation-checks</string>
<key>CFBundleExecutable</key><string>checks</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun xcstringstool compile --output-directory "$bundle/Contents/Resources" CodexLimits/Localizable.xcstrings
xcrun swiftc -target "$(uname -m)-apple-macosx14.0" -module-cache-path "${TMPDIR:-/tmp}/codexlimits-swift-module-cache" -parse-as-library -swift-version 5 \
  CodexLimitsShared/UsageModels.swift \
  CodexLimitsShared/CodexWidgetContentView.swift \
  CodexLimits/App/AppState.swift \
  CodexLimits/App/MenuBarController.swift \
  CodexLimits/App/SettingsView.swift \
  CodexLimits/App/SettingsWindowController.swift \
  CodexLimits/Usage/CodexUsageFetcher.swift \
  Tests/PresentationChecks.swift -o "$bundle/Contents/MacOS/checks"
"$bundle/Contents/MacOS/checks"
