use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use anyhow::Context;

use crate::model::{Article, State};

pub fn default_state_path() -> anyhow::Result<PathBuf> {
    let base = dirs::data_dir().context("cannot determine XDG data directory")?;
    Ok(base.join("omarchy-oma-channel").join("state.json"))
}

pub fn load_state(path: &Path) -> anyhow::Result<State> {
    match fs::read_to_string(path) {
        Ok(text) => {
            if text.trim().is_empty() {
                return Ok(State::new());
            }
            serde_json::from_str(&text).map_err(|e| anyhow::anyhow!("corrupt state file {}: {e}", path.display()))
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(State::new()),
        Err(e) => Err(anyhow::anyhow!("cannot read {}: {e}", path.display())),
    }
}

pub fn save_state(path: &Path, state: &State) -> anyhow::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("cannot create {}", parent.display()))?;
    }
    let tmp = path.with_extension("json.tmp");
    let json = serde_json::to_string_pretty(state)?;
    fs::write(&tmp, json.as_bytes()).with_context(|| format!("cannot write {}", tmp.display()))?;
    fs::rename(&tmp, path).with_context(|| format!("cannot finalize {}", path.display()))?;
    Ok(())
}

/// Merge freshly fetched feeds into the cached state.
///
/// - Successfully fetched feeds replace their previous articles entirely.
/// - Failed/unfetched feeds keep their previous articles.
/// - Read flags survive for any article whose id is still present.
/// - Bookmarked articles are permanent: they survive being dropped by an
///   unsubscribed feed, a per-feed cap truncation, or simply falling out of a
///   refetched feed's response, at any age. A snapshot is taken before the
///   normal replace/truncate/filter pipeline runs, and anything it dropped is
///   restored from cache afterwards — no network refetch required.
pub fn merge_fetch(
    state: &mut State,
    fresh: Vec<(String, Vec<Article>)>,
    enabled_urls: &[&str],
    max_per_feed: usize,
    now: i64,
) {
    let bookmarked_by_id: std::collections::HashMap<String, Article> = state
        .items
        .iter()
        .filter(|a| a.bookmarked)
        .map(|a| (a.id.clone(), a.clone()))
        .collect();

    let mut by_feed: std::collections::HashMap<String, Vec<Article>> = state
        .items
        .drain(..)
        .fold(std::collections::HashMap::new(), |mut acc, a| {
            acc.entry(a.feed_url.clone()).or_default().push(a);
            acc
        });

    for (url, mut articles) in fresh {
        sort_desc(&mut articles);
        articles.truncate(max_per_feed);
        by_feed.insert(url, articles);
    }

    let mut merged: Vec<Article> = by_feed
        .into_iter()
        .filter(|(url, _)| enabled_urls.contains(&url.as_str()))
        .flat_map(|(_, articles)| articles)
        .collect();

    for a in &mut merged {
        if let Some(saved) = bookmarked_by_id.get(&a.id) {
            a.bookmarked = true;
            a.bookmarked_at = saved.bookmarked_at;
        }
    }
    let seen: std::collections::HashSet<String> = merged.iter().map(|a| a.id.clone()).collect();
    for (id, saved) in bookmarked_by_id {
        if !seen.contains(&id) {
            merged.push(saved);
        }
    }

    sort_desc(&mut merged);
    state.items = merged;
    state.last_fetch = now;
}

fn sort_desc(articles: &mut [Article]) {
    articles.sort_by_key(|a| std::cmp::Reverse(a.sort_key()));
}
