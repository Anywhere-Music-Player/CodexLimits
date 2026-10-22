#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/codexlimits-browser-checks.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -target "$(uname -m)-apple-macosx14.0" -module-cache-path "${TMPDIR:-/tmp}/codexlimits-swift-module-cache" -parse-as-library -swift-version 5 \
  CodexLimitsShared/UsageModels.swift CodexLimits/Usage/CodexUsageFetcher.swift \
  CodexLimits/Usage/CodexAppServer.swift Tests/BrowserAuthChecks.swift -o "$build_dir/checks"
"$build_dir/checks" "$PWD/Tests/Fixtures/fake-app-server.py"
