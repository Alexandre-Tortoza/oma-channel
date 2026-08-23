# AGENTS.md

Instructions for coding agents working on the Oma Channel Omarchy plugin (`io.github.alexmrtr.oma-channel`).

## Architecture

Two layers connected by a JSON contract:

1. **Rust backend (`src/`)** — owns ALL logic and persistence:
   - `model.rs`: serde types (Article, Subscription, State, BookmarkInput, MarkInput) and the JSON shapes. `Article` carries `bookmarked`/`bookmarkedAt` (permanent, exempt from pruning) and `imageUrl`/`artworkPath`/`artworkFailed` (artwork pipeline).
   - `feed.rs`: parallel fetching (ureq, std threads), RSS 2.0/Atom parsing (feed-rs), HTTPS-only enforcement, HTML stripping/snippets, `candidate_image_url()` extraction from feed-declared media/enclosures.
   - `state.rs`: atomic state file at `$XDG_DATA_HOME/omarchy-oma-channel/state.json`; merge semantics (fetched feeds replace their items; failed feeds keep theirs; unsubscribed feeds drop) — **except** bookmarked articles, which `merge_fetch` snapshots before the pipeline and restores afterward regardless of feed/cap/subscription changes.
   - `artwork.rs`: bounded image download (2 MiB cap, HTTPS-only, MIME-sniffed via `infer` rather than trusted from the URL) into `$XDG_CACHE_HOME/omarchy-oma-channel/artwork/`, OpenGraph `og:image` scraping for the page-fetch fallback, and ownership-based orphan sweeping.
   - `opml_io.rs`: OPML 2.0 import/export with folder→category mapping.
   - `main.rs`: clap CLI — `fetch|list|mark|bookmark|prune|enrich-artwork|import-opml|export-opml`. Payloads come from `--input <json>` (QML argv path) or stdin fallback.

2. **QML frontend** — presentation only, never parses XML:
   - `Service.qml` (manifest kind `"service"`, singleton): owns every `Process` spawn (fetch/list/mark/bookmark/enrich-artwork/OPML), the in-memory article cache, settings, and the `IpcHandler` (`target: "io.github.alexmrtr.oma-channel"`, commands `refresh`/`markAllRead`/`cleanup`/`bookmarks`/`status`). One instance regardless of monitor count — a bar surface is built per monitor, so anything that fetches needs to live here, not in `BarWidget.qml`, or it fetches once per screen.
   - `BarWidget.qml` (manifest kind `"bar-widget"`, one instance **per monitor**): thin proxy over `bar.shell.serviceFor(moduleName)`; owns only the bar icon, the popup `Panel.qml` loader, and per-monitor placement (`barSection`, `legacySettings` migration from `bar.layoutConfig`). Panel open/close/toggle work for free via the shell's generic `omarchy-shell shell summon|hide|toggle <pluginId>` (routes to the focused monitor's instance using the `open()`/`close()`/`opened` contract already on `BarWidget`); `bookmarks()` is the one IPC command that needs its own routing (via `Service.qml`, since it must set a filter, not just open) and broadcasts to every live widget via `bar.moduleWidgets(pluginId)`.
   - `Model.js`: pure JS helpers (filtering, pagination, categories, bookmarks) plus the Rust→QML adapter (`adaptRustItems`, `collectReadIds`, `setItemsRead`, `setItemsBookmarked`). Rust field names are camelCase (`feedUrl`, `pubDateMs` derived from `published * 1000`, `artworkPath`). Kept lean deliberately — every exported function must be reachable from a `Model.xxx` call in some `.qml` file (directly or via another live function); dead code has been swept once already (a leftover client-side feed-parsing pipeline from the template this was adapted from) and should not be allowed to regrow.
   - Read flags live on items themselves (`item.read`); marking calls `mark --input {"ids":[...],"read":bool}` optimistically. Bookmarks follow the identical pattern via `bookmark --input {"ids":[...],"bookmarked":bool}`.
   - Artwork thumbnails in `ArticleRow.qml` only ever bind to the local `item.artworkPath` (`file://` path already downloaded and MIME-sniffed by the backend) — never to a remote feed-provided URL.

## Invariants

- Article identity = stable FNV hash of link+title (`id`); never regenerate per fetch.
- Only `https://` URLs are fetched or opened — feeds, artwork downloads, and OpenGraph page fetches alike.
- A bookmarked article never disappears: not on retention prune, not on a per-feed cap truncation, not on unsubscribing its feed. This is enforced in `state::merge_fetch`/`State::prune_retention`, pinned by `tests/core.rs`'s `bookmark_survives_*` tests.
- The binary must be rebuilt after any `src/` change: `./install.sh` or `cargo build --release && cp target/release/oma-channel bin/`.
- Settings keys: `subscriptions`, `pollIntervalMinutes`, `maxItemsPerFeed`, `itemsPerPage`, `retentionDays`, `unreadOnlyDefault`, `barSection`, `artworkEnabled`, `artworkAllowPageFetch`.
- `Service.qml` requires both `stateReady` (cache loaded from disk) and `settingsReady` (a per-monitor `BarWidget` has pushed `shell.json` settings via `configure()`) before `fetchFeed()` will run — this guards a startup race between the two, since services get no `settings` injection of their own.

## Verification

```bash
cargo test
cargo clippy --all-targets -- -D warnings
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell/ BarWidget.qml Panel.qml Service.qml ReaderView.qml SettingsView.qml SubscriptionsView.qml ArticleRow.qml CategoryDrawer.qml SearchField.qml   # if available
```

Live reload after QML edits: `omarchy-shell shell rescanPlugins`.

Scripting/keybinding surface (once installed):

```bash
omarchy-shell shell summon io.github.alexmrtr.oma-channel     # open the panel (focused monitor)
omarchy-shell shell hide io.github.alexmrtr.oma-channel
omarchy-shell shell toggle io.github.alexmrtr.oma-channel
omarchy-shell io.github.alexmrtr.oma-channel refresh
omarchy-shell io.github.alexmrtr.oma-channel markAllRead
omarchy-shell io.github.alexmrtr.oma-channel cleanup
omarchy-shell io.github.alexmrtr.oma-channel bookmarks         # open panel, "Saved" filter applied
omarchy-shell io.github.alexmrtr.oma-channel status            # JSON: counts, unread, isFetching
```
