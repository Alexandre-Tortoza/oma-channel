use std::io::Read;

use anyhow::{bail, Context};
use clap::{Parser, Subcommand};

use oma_channel::model::{
    Article, BookmarkInput, FetchOutput, FetchStats, MarkInput, State, SubscriptionsPayload,
};
use oma_channel::{artwork, feed, model, opml_io, state, tray};

#[derive(Parser)]
#[command(
    name = "oma-channel",
    version,
    about = "Rust backend for the Oma Channel Omarchy bar plugin"
)]
struct Cli {
    /// Override the default state file location.
    #[arg(long, global = true)]
    state: Option<std::path::PathBuf>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Fetch all enabled feeds (subscriptions JSON via --input or stdin), merge into cache.
    Fetch {
        #[arg(long, default_value_t = 20)]
        max_per_feed: usize,
        #[arg(long, default_value_t = 30)]
        retention_days: u32,
        #[arg(long, default_value_t = 8)]
        concurrency: usize,
        #[arg(long)]
        input: Option<String>,
    },
    /// Print cached articles as JSON.
    List,
    /// Mark article ids read/unread ({"ids":[...],"read":bool} via --input or stdin).
    Mark {
        #[arg(long)]
        input: Option<String>,
    },
    /// Bookmark/unbookmark article ids ({"ids":[...],"bookmarked":bool} via --input or stdin).
    Bookmark {
        #[arg(long)]
        input: Option<String>,
    },
    /// Drop articles older than the retention window.
    Prune {
        #[arg(long, default_value_t = 30)]
        retention_days: u32,
    },
    /// Download artwork for a bounded batch of articles that have a feed-declared
    /// image but no cached copy yet, and sweep orphaned files from the cache.
    EnrichArtwork {
        #[arg(long, default_value_t = 6)]
        budget: usize,
        /// Also read an article's own page for its OpenGraph image when the
        /// feed didn't declare one. An extra request to the publisher per
        /// article, so it defaults off. (presence-flag; bool fields default false)
        #[arg(long)]
        allow_page_fetch: bool,
        /// Real kill switch: with this flag absent, nothing leaves the machine.
        #[arg(long)]
        network: bool,
    },
    /// Publish a StatusNotifierItem tray icon and run until killed. Long-running;
    /// meant to be managed as a persistent process by the QML service layer.
    Tray,
    /// Parse an OPML file and print its feeds as subscriptions JSON.
    ImportOpml { path: std::path::PathBuf },
    /// Export subscriptions (JSON via --input or stdin) to an OPML 2.0 file.
    ExportOpml {
        path: std::path::PathBuf,
        #[arg(long)]
        input: Option<String>,
    },
}

fn main() {
    let cli = Cli::parse();
    if let Err(err) = run(cli) {
        eprintln!("error: {err:#}");
        std::process::exit(1);
    }
}

fn run(cli: Cli) -> anyhow::Result<()> {
    let state_path = match cli.state {
        Some(p) => p,
        None => state::default_state_path()?,
    };

    match cli.command {
        Command::Fetch {
            max_per_feed,
            retention_days,
            concurrency,
            input,
        } => cmd_fetch(&state_path, max_per_feed, retention_days, concurrency, input),
        Command::List => cmd_list(&state_path),
        Command::Mark { input } => cmd_mark(&state_path, input),
        Command::Bookmark { input } => cmd_bookmark(&state_path, input),
        Command::Prune { retention_days } => cmd_prune(&state_path, retention_days),
        Command::EnrichArtwork {
            budget,
            allow_page_fetch,
            network,
        } => cmd_enrich_artwork(&state_path, budget, allow_page_fetch, network),
        Command::Tray => tray::run(&state_path),
        Command::ImportOpml { path } => cmd_import_opml(&path),
        Command::ExportOpml { path, input } => cmd_export_opml(&path, input),
    }
}

/// Payload from --input argument (QML argv) or stdin fallback.
fn read_payload(input: Option<String>) -> anyhow::Result<String> {
    match input {
        Some(text) => Ok(text),
        None => read_stdin(),
    }
}

fn read_stdin() -> anyhow::Result<String> {
    let mut buf = String::new();
    std::io::stdin()
        .read_to_string(&mut buf)
        .context("cannot read stdin")?;
    Ok(buf)
}
/// Accept either {"subscriptions":[...]} or a bare [...] array.
fn parse_subscriptions(text: &str) -> anyhow::Result<Vec<model::Subscription>> {
    let text = text.trim();
    if text.is_empty() {
        return Ok(Vec::new());
    }
    if let Ok(payload) = serde_json::from_str::<SubscriptionsPayload>(text) {
        return Ok(payload.subscriptions);
    }
    serde_json::from_str::<Vec<model::Subscription>>(text)
        .context("expected subscriptions JSON object or array")
}

fn parse_mark_input(text: &str) -> anyhow::Result<MarkInput> {
    serde_json::from_str::<MarkInput>(text.trim()).context("expected {\"ids\":[...],\"read\":bool}")
}

fn parse_bookmark_input(text: &str) -> anyhow::Result<BookmarkInput> {
    serde_json::from_str::<BookmarkInput>(text.trim())
        .context("expected {\"ids\":[...],\"bookmarked\":bool}")
}

fn output_state(state: &State, extra_stats: Option<FetchStats>) -> anyhow::Result<()> {
    let unread = state.unread_count();
    let items = state.items_with_read();
    match extra_stats {
        Some(stats) => println!(
            "{}",
            serde_json::to_string(&FetchOutput {
                ok: true,
                stats,
                items,
            })?
        ),
        None => println!(
            "{}",
            serde_json::to_string(&serde_json::json!({
                "ok": true,
                "unread": unread,
                "items": items,
            }))?
        ),
    }
    Ok(())
}

fn cmd_fetch(
    path: &std::path::Path,
    max_per_feed: usize,
    retention_days: u32,
    concurrency: usize,
    input: Option<String>,
) -> anyhow::Result<()> {
    let subs = parse_subscriptions(&read_payload(input)?)?;
    let enabled: Vec<model::Subscription> = subs.into_iter().filter(|s| s.enabled).collect();
    for sub in &enabled {
        feed::https_only(&sub.url)?;
    }
    let enabled_urls: Vec<&str> = enabled.iter().map(|s| s.url.as_str()).collect();

    let results = feed::fetch_all(&enabled, concurrency);
    let total_feeds = results.len();

    let mut fresh: Vec<(String, Vec<Article>)> = Vec::new();
    let mut fetched = 0usize;
    let mut failed = 0usize;
    for (url, result) in results {
        match result {
            Ok(articles) => {
                fetched += 1;
                fresh.push((url, articles));
            }
            Err(err) => {
                failed += 1;
                eprintln!("warn: {url}: {err:#}");
            }
        }
    }

    let mut st = state::load_state(path)?;
    let known_before: std::collections::HashSet<String> =
        st.items.iter().map(|a| a.id.clone()).collect();

    let now = feed::now_secs();
    state::merge_fetch(&mut st, fresh, &enabled_urls, max_per_feed, now);
    st.prune_retention(retention_days, now);
    state::save_state(path, &st)?;

    let new_articles = st.items.iter().filter(|a| !known_before.contains(&a.id)).count();
    let stats = FetchStats {
        total_feeds,
        fetched,
        failed,
        new_articles,
        total_items: st.items.len(),
        unread: st.unread_count(),
    };
    output_state(&st, Some(stats))
}

fn cmd_list(path: &std::path::Path) -> anyhow::Result<()> {
    let st = state::load_state(path)?;
    output_state(&st, None)
}

fn cmd_mark(path: &std::path::Path, input: Option<String>) -> anyhow::Result<()> {
    let parsed = parse_mark_input(&read_payload(input)?)?;
    let mut st = state::load_state(path)?;
    for id in &parsed.ids {
        st.set_read(id, parsed.read);
    }
    state::save_state(path, &st)?;
    output_state(&st, None)
}

fn cmd_bookmark(path: &std::path::Path, input: Option<String>) -> anyhow::Result<()> {
    let parsed = parse_bookmark_input(&read_payload(input)?)?;
    let mut st = state::load_state(path)?;
    let now = feed::now_secs();
    for id in &parsed.ids {
        st.set_bookmarked(id, parsed.bookmarked, now);
    }
    state::save_state(path, &st)?;
    output_state(&st, None)
}

fn cmd_prune(path: &std::path::Path, retention_days: u32) -> anyhow::Result<()> {
    let mut st = state::load_state(path)?;
    let removed = st.prune_retention(retention_days, feed::now_secs());
    state::save_state(path, &st)?;
    println!(
        "{}",
        serde_json::json!({"ok": true, "removed": removed, "totalItems": st.items.len()})
    );
    Ok(())
}

/// Downloads artwork for a bounded batch of articles per invocation rather
/// than folding this into `fetch`: image downloads have a different latency
/// and failure profile than feed fetches, and coupling them would make
/// `fetch`'s own timing unpredictable. This is meant to be invoked lazily,
/// on a schedule, after `fetch` completes, and re-invoked until it reports
/// nothing left to do.
fn cmd_enrich_artwork(
    path: &std::path::Path,
    budget: usize,
    allow_page_fetch: bool,
    network: bool,
) -> anyhow::Result<()> {
    if !network {
        let st = state::load_state(path)?;
        println!(
            "{}",
            serde_json::to_string(&serde_json::json!({
                "ok": true,
                "enriched": 0,
                "attempted": 0,
                "swept": 0,
                "unread": st.unread_count(),
                "items": st.items_with_read(),
            }))?
        );
        return Ok(());
    }

    let mut st = state::load_state(path)?;
    let cache_dir = artwork::cache_dir()?;

    // Newest-first, so a cold cache fills in with the stories most likely to
    // still be on screen rather than ones about to age out.
    let mut ids: Vec<String> = st.items.iter().map(|a| a.id.clone()).collect();
    ids.sort_by_key(|id| {
        std::cmp::Reverse(st.items.iter().find(|a| &a.id == id).map(|a| a.sort_key()).unwrap_or(0))
    });

    let mut attempted = 0usize;
    let mut enriched = 0usize;

    // Pass 1: download artwork the feed already named. Runs whenever the
    // network is allowed at all, since it contacts no server the feed didn't
    // already point at.
    for id in &ids {
        if attempted >= budget {
            break;
        }
        let (image_url, eligible) = match st.items.iter().find(|a| &a.id == id) {
            Some(a) => (
                a.image_url.clone(),
                a.image_url.is_some() && a.artwork_path.is_none() && !a.artwork_failed,
            ),
            None => (None, false),
        };
        if !eligible {
            continue;
        }
        attempted += 1;
        let url = image_url.unwrap();
        match artwork::download_image(&url, &cache_dir) {
            Ok(dest) => {
                if let Some(a) = st.items.iter_mut().find(|a| &a.id == id) {
                    a.artwork_path = Some(dest.to_string_lossy().into_owned());
                }
                enriched += 1;
            }
            Err(err) => {
                eprintln!("warn: artwork {url}: {err:#}");
                if let Some(a) = st.items.iter_mut().find(|a| &a.id == id) {
                    a.artwork_failed = true;
                }
            }
        }
    }

    // Pass 2 (opt-in): the feed named nothing, so read the article's own page
    // for an OpenGraph image. A request to a server the feed itself did not
    // point at, which is exactly what the setting gates.
    if allow_page_fetch {
        for id in &ids {
            if attempted >= budget {
                break;
            }
            let (link, eligible) = match st.items.iter().find(|a| &a.id == id) {
                Some(a) => (
                    a.link.clone(),
                    a.image_url.is_none() && a.artwork_path.is_none() && !a.artwork_failed,
                ),
                None => (String::new(), false),
            };
            if !eligible {
                continue;
            }
            attempted += 1;
            let outcome = artwork::fetch_og_image(&link).and_then(|found| match found {
                Some(image_url) => artwork::download_image(&image_url, &cache_dir).map(|dest| (image_url, dest)),
                None => anyhow::bail!("no artwork on the page"),
            });
            match outcome {
                Ok((image_url, dest)) => {
                    if let Some(a) = st.items.iter_mut().find(|a| &a.id == id) {
                        a.image_url = Some(image_url);
                        a.artwork_path = Some(dest.to_string_lossy().into_owned());
                    }
                    enriched += 1;
                }
                Err(err) => {
                    eprintln!("warn: artwork page {link}: {err:#}");
                    if let Some(a) = st.items.iter_mut().find(|a| &a.id == id) {
                        a.artwork_failed = true;
                    }
                }
            }
        }
    }

    state::save_state(path, &st)?;
    let swept = artwork::sweep_orphaned(&st, &cache_dir).unwrap_or(0);
    // Mirrors output_state's shape (unread + items) so the QML side can apply
    // this result the same way it applies fetch/mark/bookmark output, picking
    // up any newly downloaded artwork_path without a second round trip.
    println!(
        "{}",
        serde_json::to_string(&serde_json::json!({
            "ok": true,
            "enriched": enriched,
            "attempted": attempted,
            "swept": swept,
            "unread": st.unread_count(),
            "items": st.items_with_read(),
        }))?
    );
    Ok(())
}

fn cmd_import_opml(path: &std::path::Path) -> anyhow::Result<()> {
    const MAX_OPML_BYTES: u64 = 5 * 1024 * 1024;
    let meta = std::fs::metadata(path).with_context(|| format!("cannot stat {}", path.display()))?;
    if !meta.is_file() {
        bail!("not a regular file");
    }
    if meta.len() > MAX_OPML_BYTES {
        bail!("file exceeds 5 MiB limit");
    }
    let xml = std::fs::read_to_string(path)
        .with_context(|| format!("cannot read {}", path.display()))?;
    let out = opml_io::import(&xml)?;
    println!("{}", serde_json::to_string(&out)?);
    Ok(())
}

fn cmd_export_opml(path: &std::path::Path, input: Option<String>) -> anyhow::Result<()> {
    let subs = parse_subscriptions(&read_payload(input)?)?;
    let count = opml_io::write_export(path, &subs)?;
    println!(
        "{}",
        serde_json::json!({"ok": true, "exported": count})
    );
    Ok(())
}
