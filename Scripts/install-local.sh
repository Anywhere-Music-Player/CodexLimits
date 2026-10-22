#!/bin/bash
# Build, sign, replace, and launch the local release app without opening Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."
repo_dir="$PWD"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/codexlimits-install.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
product="$build_dir/DerivedData/Build/Products/Release/CodexLimits.app"
destination=/Applications/CodexLimits.app
bundle_id=com.buildsucceeded.codex-limits

cat > "$build_dir/AppControl.swift" <<'SWIFT'
import AppKit
import Foundation
let bundleID = "com.buildsucceeded.codex-limits"
if CommandLine.arguments[1] == "stop" {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    apps.forEach { _ = $0.terminate() }
    let deadline = Date().addingTimeInterval(10)
    while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    for app in apps where !app.isTerminated { _ = app.forceTerminate() }
    let forceDeadline = Date().addingTimeInterval(3)
    while apps.contains(where: { !$0.isTerminated }) && Date() < forceDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard apps.allSatisfy(\.isTerminated) else { fputs("Could not stop CodexLimits.\n", stderr); exit(1) }
} else {
    let expected = URL(fileURLWithPath: "/Applications/CodexLimits.app").standardizedFileURL
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: {
            $0.bundleURL?.standardizedFileURL == expected && !$0.isTerminated
        }) {
            // Confirm the process stays alive beyond initial launch.
            RunLoop.current.run(until: Date().addingTimeInterval(3))
            guard !app.isTerminated else { fputs("CodexLimits exited after launch.\n", stderr); exit(1) }
            print("Running PID \(app.processIdentifier): \(expected.path)")
            exit(0)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    fputs("CodexLimits did not start.\n", stderr)
    exit(1)
}
SWIFT
xcrun swiftc "$build_dir/AppControl.swift" -o "$build_dir/app-control"

printf 'Building and signing CodexLimits…\n'
if ! xcodebuild -project "$repo_dir/CodexLimits.xcodeproj" -scheme CodexLimits \
    -configuration Release -derivedDataPath "$build_dir/DerivedData" \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES build > "$build_dir/build.log" 2>&1; then
    cat "$build_dir/build.log"
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$product"
/usr/bin/codesign --verify --strict "$product/Contents/PlugIns/CodexLimitsWidgetExtension.appex"
actual_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$product/Contents/Info.plist")
[[ "$actual_id" == "$bundle_id" ]] || { printf 'Unexpected build bundle ID.\n' >&2; exit 1; }
if [[ -e "$destination" ]]; then
    installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
    [[ "$installed_id" == "$bundle_id" ]] || { printf 'Unexpected installed bundle ID.\n' >&2; exit 1; }
fi

# Stage the complete verified bundle before stopping the installed application.
staging_root=$(mktemp -d /Applications/.codexlimits-install.XXXXXX)
staged="$staging_root/CodexLimits.app"
if ! /usr/bin/ditto "$product" "$staged"; then rmdir "$staging_root" 2>/dev/null || true; exit 1; fi
/usr/bin/codesign --verify --deep --strict "$staged"
"$build_dir/app-control" stop
backup=""
if [[ -e "$destination" ]]; then
    backup_root="$HOME/Library/Application Support/CodexLimits/LocalBuildBackups"
    mkdir -p "$backup_root"
    backup_parent=$(mktemp -d "$backup_root/previous.XXXXXX")
    backup="$backup_parent/CodexLimits.app"
    mv "$destination" "$backup"
    printf 'Previous app saved to: %s\n' "$backup"
fi
if ! mv "$staged" "$destination"; then
    [[ -z "$backup" ]] || mv "$backup" "$destination"
    exit 1
fi
rmdir "$staging_root"
# Stop only the old CodexLimits widget executable so WidgetKit can load the new one.
/usr/bin/pkill -x CodexLimitsWidgetExtension 2>/dev/null || true
/usr/bin/open "$destination"
if ! "$build_dir/app-control" verify; then
    printf 'Launch failed; restoring the previous application.\n' >&2
    "$build_dir/app-control" stop || true
    failed_parent=$(mktemp -d "${TMPDIR:-/tmp}/codexlimits-failed.XXXXXX")
    mv "$destination" "$failed_parent/CodexLimits.app"
    if [[ -n "$backup" ]]; then
        mv "$backup" "$destination"
        /usr/bin/open "$destination"
    fi
    exit 1
fi
/usr/bin/cmp "$product/Contents/MacOS/CodexLimits" "$destination/Contents/MacOS/CodexLimits"
/usr/bin/codesign --verify --deep --strict "$destination"
/usr/bin/open -a "$destination" 'codex-limits://open-settings'
printf 'Installed, signature verified, and launched: %s\n' "$destination"
