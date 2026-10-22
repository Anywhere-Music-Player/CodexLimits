#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/codexlimits-login-probe.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
bundle="$build_dir/CodexLimitsBrowserProbe.app"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.buildsucceeded.codex-limits.browser-prototype</string>
<key>CFBundleExecutable</key><string>probe</string>
<key>CFBundleName</key><string>CodexLimits Browser Probe</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cat > "$build_dir/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.network.server</key><true/>
</dict></plist>
PLIST
xcrun swiftc -target "$(uname -m)-apple-macosx14.0" -module-cache-path "${TMPDIR:-/tmp}/codexlimits-swift-module-cache" -parse-as-library -swift-version 5 \
  CodexLimitsShared/UsageModels.swift CodexLimits/Usage/CodexUsageFetcher.swift \
  CodexLimits/Usage/CodexAppServer.swift Tests/BrowserLoginProbe.swift -o "$bundle/Contents/MacOS/probe"
codesign --force --sign - --entitlements "$build_dir/entitlements.plist" "$bundle"
"$bundle/Contents/MacOS/probe"
