#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/codexlimits-login-checks.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -target "$(uname -m)-apple-macosx14.0" -module-cache-path "${TMPDIR:-/tmp}/codexlimits-swift-module-cache" -parse-as-library -swift-version 5 CodexLimits/App/LaunchAtLogin.swift Tests/LaunchAtLoginChecks.swift -o "$build_dir/checks"
"$build_dir/checks"
