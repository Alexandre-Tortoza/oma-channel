# Oma Channel

Native RSS/Atom reader for the **Omarchy** bar with a **Rust backend**: OPML import/export, categories, unread tracking, live search, permanent bookmarks, article artwork, configurable retention, and IPC for scripting/keybinding.

Inspired by [sanjyay/rss-reeder](https://github.com/sanjyay/rss-reeder) (which itself credits [rafaelvzago/omarchy-rss-plugin](https://github.com/rafaelvzago/omarchy-rss-plugin)), with bookmarks/artwork/IPC ideas borrowed from [alejandro-llanes/omarchy-news](https://github.com/alejandro-llanes/omarchy-news) and adapted to this plugin's Rust-backed architecture. This plugin replaces the QML/JS feed pipeline with a compiled Rust core:

| Layer | Tech | Responsibility |
|---|---|---|
| `oma-channel` binary | Rust (`ureq`, `feed-rs`, `serde`, `infer`, `ksni`) | Parallel HTTPS fetching, RSS 2.0/Atom parsing, read/bookmark state, artwork download, retention pruning, OPML 2.0, system tray publishing |
| `Service.qml` | Quickshell (Omarchy shell), singleton | Owns every backend request, the article cache, settings, and IPC — one instance regardless of monitor count |
| `BarWidget.qml` / `Panel.qml` / `*.qml` | Quickshell (Omarchy shell), per-monitor | Bar badge, popup panel, search/filter UI, settings — a thin view over `Service.qml` |

The QML layer never parses XML — it spawns the Rust binary and renders its JSON.

## Features

- RSS 2.0 + Atom 1.0, HTTPS-only, size/time-limited, fetched in parallel threads
- Unread badge in the bar; auto-mark-read on open
- **Permanent bookmarks** — a bookmarked article survives retention pruning, the per-feed item cap, and unsubscribing its feed, at any age
- **Article artwork** — thumbnails pulled from feed-declared media (or, optionally, the article page's OpenGraph image), downloaded and MIME-sniffed locally; cards only ever render the local cached file, never a remote URL
- Categories with drawer filtering; create categories inline when adding feeds
- Live search across titles, snippets, feeds and categories
- OPML 2.0 import/export via native portal file dialogs (folders preserved)
- Per-feed item caps, retention pruning (1–3650 days), configurable polling
- Vim-style keys: `j/k` navigate, `Enter` open, `m` toggle read, `b` bookmark, `r` refresh, `/` search, `c` categories
- **Scriptable via IPC** — bind hotkeys to open the panel, refresh, mark all read, or jump straight to saved articles (see [Keybinding it](#keybinding-it))
- **Optional system tray icon** — tuck the plugin away in the tray's hover drawer (like Steam/Discord) instead of always showing in the bar; left-click opens the panel, right-click gives a small menu
- Persistent state in `$XDG_DATA_HOME/omarchy-oma-channel/state.json`; artwork cache in `$XDG_CACHE_HOME/omarchy-oma-channel/artwork/`

## Install

```bash
git clone <this-repo-url>
cd oma-channel
./install.sh
```

The script builds the backend with cargo, copies the binary into the plugin folder and `~/.local/bin`, validates the manifest, enables the plugin and reloads the shell.

### Updating

```bash
git pull && ./install.sh
```

## Usage

1. Click the 󰑫 icon in the bar (right section by default).
2. Open Settings (󰒓) → **Manage feeds** to add feed URLs.
3. Or import your subscriptions: Settings → **Import OPML file**.
4. Press `b` (or click the star) on an article to bookmark it — the **Saved** chip in the reader toolbar filters to those.
5. Settings → **ARTWORK** to turn thumbnails on/off, and separately whether the reader may read an article's own page for a picture the feed didn't provide.
6. Settings → **TRAY** → "Show in system tray instead of the bar" to move the icon into the tray's hover drawer. Needs a running StatusNotifierWatcher, which Omarchy's own tray widget already provides — if none is available the daemon retries a few times with backoff, then gives up quietly (check `journalctl`/the shell's own log for `[OMA-CHANNEL]` if the icon never shows up).

## Keybinding it

The panel and a few actions answer to Omarchy's own IPC, so any Hyprland binding can reach them:

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER SHIFT", "R", "omarchy-shell shell toggle io.github.alexmrtr.oma-channel")
```

The full surface:

```bash
omarchy-shell shell summon io.github.alexmrtr.oma-channel   # open the panel (focused monitor)
omarchy-shell shell hide io.github.alexmrtr.oma-channel
omarchy-shell shell toggle io.github.alexmrtr.oma-channel
omarchy-shell io.github.alexmrtr.oma-channel refresh        # fetch now
omarchy-shell io.github.alexmrtr.oma-channel markAllRead
omarchy-shell io.github.alexmrtr.oma-channel cleanup        # apply retention + cap now
omarchy-shell io.github.alexmrtr.oma-channel bookmarks      # open the panel on saved articles
omarchy-shell io.github.alexmrtr.oma-channel status         # JSON: counts, unread, isFetching
```

## Development

```bash
cargo test              # backend unit/integration tests
cargo clippy --all-targets -- -D warnings
qmllint -I /usr/share/omarchy/shell/ BarWidget.qml Panel.qml Service.qml ReaderView.qml SettingsView.qml SubscriptionsView.qml ArticleRow.qml CategoryDrawer.qml SearchField.qml   # if qmllint is available
omarchy plugin validate .
```

Backend CLI:

```bash
oma-channel list
echo '{"subscriptions":[{"url":"https://blog.rust-lang.org/feed.xml"}]}' \
  | oma-channel fetch --max-per-feed 10 --retention-days 30
oma-channel bookmark --input '{"ids":["<article-id>"],"bookmarked":true}'
oma-channel enrich-artwork --budget 6 --network            # add --allow-page-fetch to also scrape OpenGraph images
oma-channel tray                                            # long-running; publishes the tray icon and blocks
oma-channel import-opml subs.opml
```

State lives at `~/.local/share/omarchy-oma-channel/state.json`; artwork cache at `~/.cache/omarchy-oma-channel/artwork/`; plugin settings live in Omarchy's `shell.json`.

## License

MIT — see [LICENSE](LICENSE). UI adapted from [rss-reeder](https://github.com/sanjyay/rss-reeder) (MIT).
