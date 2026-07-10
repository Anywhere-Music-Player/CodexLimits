# CodexLimits Contributor Notes

## Purpose

CodexLimits is a macOS menu bar app and WidgetKit extension that display ChatGPT Codex 5-hour and weekly usage percentages.

## Scope

- Keep the project Codex-only.
- Do not add Claude, Copilot, Wake Up, Sparkle, ccusage, or external update systems.
- Keep source code and documentation in English.
- Preserve localization resources and add new UI strings to every supported localization.
- Keep the refresh choices limited to 1, 2, 3, and 5 minutes.

## Structure

- `CodexLimits/`: app entry point, menu bar, settings, web login, and Codex fetcher.
- `CodexLimitsShared/`: snapshot storage, refresh settings, and shared models.
- `CodexLimitsWidget/`: the single Codex usage widget.

## Identifiers

- App: `com.buildsucceeded.codex-limits`
- Widget: `com.buildsucceeded.codex-limits.widget`
- App Group: `group.com.buildsucceeded.codex-limits`

## Data flow

1. The app authenticates through an embedded `WKWebView`.
2. The app fetches the Codex usage endpoint every configured interval.
3. The app stores `usage_snapshot.json` in the App Group container.
4. The menu bar reads the live app state.
5. The widget reads the shared snapshot and schedules its next timeline refresh.
