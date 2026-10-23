# OpenUsage project context

OpenUsage is a SwiftPM-based SwiftUI menu-bar app for macOS. It displays AI provider usage widgets for Claude, Codex, Cursor, Grok, Devin and other providers.

## Development and releases

The native Swift edition develops on `main`. The original Tauri edition lives on `tauri-legacy`, whose final release is `v0.6.28`. Native versions start at `0.7.x`.

`.github/workflows/release.yml` publishes the Sparkle appcast on `gh-pages`. Beta tags use `-beta.N`, GitHub pre-releases and Sparkle's beta channel. Plain tags identify stable releases and GitHub Latest. The release workflow carries forward the legacy `latest.json`, allowing remaining `0.6.x` installations to find `v0.6.28`. The release-swift skill documents release commands, changelog generation and publication checks.

The app is a long-lived menu-bar process without hot reload. A rebuilt executable takes effect when that executable is launched.

## Architecture

- SwiftPM executable target; SwiftUI content is hosted in an AppKit-owned `NSStatusItem` and a custom key-capable `NSPanel`.
- Swift 6 with strict concurrency.
- Providers implement `ProviderRuntime`. An auth store reads local credentials, a usage client calls the provider API, and a mapper normalises responses into `MetricLine` values for rendering.
- `docs/` contains behaviour documentation, the architecture overview and provider-development references.

## Provider modules

Modules live under `Sources/OpenUsage/Providers/<Name>/`. `ProviderRuntime` exposes `refresh()` and `hasLocalCredentials()`. The local credential probe supports `FirstLaunchSetup` and `NewProviderSeeder`; auth-store loaders define local sources and usability filters. See `docs/adding-a-provider.md` and `docs/provider-enablement.md`.

All spend imputation for Claude, Codex, Cursor and Grok uses `Sources/OpenUsage/Pricing/` and is documented in `docs/pricing.md`. Cursor-native rates and aliases live in `Sources/OpenUsage/Resources/pricing_supplement.json`, with `updated_at`, pricing entries and `alias_rules` for CSV model slugs. [Cursor models and pricing](https://cursor.com/docs/models-and-pricing.md) supplies source data. Merging to `main` publishes the supplement to gh-pages for installed apps. `script/update_pricing_snapshots.sh` regenerates bundled LiteLLM/models.dev snapshots.

The default provider array in `AppContainer` seeds `LayoutStore` and `resetToDefault`: Claude, Codex and Cursor are followed by other providers alphabetically by display name.

Metric defaults are represented by:

1. `DefaultLayout.metricIDs`: enabled metrics.
2. `DefaultLayout.expandedMetricIDs`: Always Visible versus On Demand metrics.
3. `DefaultLayout.pinnedMetricIDs`: menu-bar pins.
4. `widgetDescriptors` declaration order: ordering within a provider.

The dashboard promotes all metrics when a provider has no Always Visible row; a fully On Demand provider therefore does not appear as such in the UI.

## UI and errors

The app has title-case headings, an established visual language and a `hoverTooltip` component. Error reporting includes a log file, PostHog and user-facing errors.

## Review material

Common PR-description sections include a plain-English summary, prior behaviour, changes, relevant follow-ups, verification and screenshots. The `docs/` tree records product behaviour and implementation context.
