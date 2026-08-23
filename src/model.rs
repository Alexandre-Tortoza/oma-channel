use serde::{Deserialize, Serialize};

pub const STATE_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Subscription {
    pub url: String,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub category: Option<String>,
    #[serde(default = "default_true")]
    pub enabled: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SubscriptionsPayload {
    #[serde(default)]
    pub subscriptions: Vec<Subscription>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Article {
    pub id: String,
    pub feed_url: String,
    pub feed_title: String,
    #[serde(default)]
    pub category: Option<String>,
    pub title: String,
    pub link: String,
    #[serde(default)]
    pub summary: String,
    /// Unix seconds; 0 when the feed provides no date.
    pub published: i64,
    pub fetched_at: i64,
    /// Not persisted; filled at output time from the state's read set.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub read: bool,
    #[serde(default)]
    pub bookmarked: bool,
    /// Unix seconds when bookmarked; 0 when not bookmarked.
    #[serde(default)]
    pub bookmarked_at: i64,
    /// Candidate artwork URL surfaced by the feed itself (media:thumbnail/content, enclosure).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_url: Option<String>,
    /// Local cache path once artwork has been downloaded.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artwork_path: Option<String>,
    /// Set once an artwork download/lookup has failed, so it is not retried every run.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub artwork_failed: bool,
}

impl Article {
    pub fn sort_key(&self) -> i64 {
        if self.published > 0 {
            self.published
        } else {
            self.fetched_at
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct State {
    pub version: u32,
    #[serde(default)]
    pub items: Vec<Article>,
    /// Sorted unique article ids already read.
    #[serde(default)]
    pub read_ids: Vec<String>,
    #[serde(default)]
    pub last_fetch: i64,
}

impl State {
    pub fn new() -> Self {
        State {
            version: STATE_VERSION,
            items: Vec::new(),
            read_ids: Vec::new(),
            last_fetch: 0,
        }
    }

    pub fn is_read(&self, id: &str) -> bool {
        self.read_ids.binary_search_by(|probe| probe.as_str().cmp(id)).is_ok()
    }

    pub fn set_read(&mut self, id: &str, read: bool) -> bool {
        let pos = self.read_ids.binary_search_by(|probe| probe.as_str().cmp(id));
        match (read, pos) {
            (true, Ok(_)) => false,
            (true, Err(idx)) => {
                self.read_ids.insert(idx, id.to_string());
                true
            }
            (false, Ok(idx)) => {
                self.read_ids.remove(idx);
                true
            }
            (false, Err(_)) => false,
        }
    }

    pub fn unread_count(&self) -> usize {
        self.items.iter().filter(|a| !self.is_read(&a.id)).count()
    }

    /// Sets an article's bookmark flag by id. Returns false if the id is
    /// unknown or the flag was already at the requested value.
    pub fn set_bookmarked(&mut self, id: &str, bookmarked: bool, now: i64) -> bool {
        match self.items.iter_mut().find(|a| a.id == id) {
            Some(a) if a.bookmarked != bookmarked => {
                a.bookmarked = bookmarked;
                a.bookmarked_at = if bookmarked { now } else { 0 };
                true
            }
            _ => false,
        }
    }

    pub fn bookmarked_count(&self) -> usize {
        self.items.iter().filter(|a| a.bookmarked).count()
    }

    /// Items cloned with their read flag populated for JSON output.
    pub fn items_with_read(&self) -> Vec<Article> {
        self.items
            .iter()
            .map(|a| {
                let mut copy = a.clone();
                copy.read = self.is_read(&a.id);
                copy
            })
            .collect()
    }

    /// Drop articles older than `retention_days` (based on sort key).
    pub fn prune_retention(&mut self, retention_days: u32, now: i64) -> usize {
        let cutoff = now - (retention_days as i64) * 86_400;
        let before = self.items.len();
        self.items
            .retain(|a| a.bookmarked || a.sort_key() >= cutoff || a.sort_key() == 0);
        before - self.items.len()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MarkInput {
    #[serde(default)]
    pub ids: Vec<String>,
    #[serde(default)]
    pub read: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct BookmarkInput {
    #[serde(default)]
    pub ids: Vec<String>,
    #[serde(default)]
    pub bookmarked: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FetchStats {
    pub total_feeds: usize,
    pub fetched: usize,
    pub failed: usize,
    pub new_articles: usize,
    pub total_items: usize,
    pub unread: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FetchOutput {
    pub ok: bool,
    pub stats: FetchStats,
    pub items: Vec<Article>,
}

#[derive(Debug, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct OpmlImportOutput {
    pub feeds: Vec<Subscription>,
    pub total_found: usize,
    pub invalid: usize,
}

/// FNV-1a 64-bit hash as hex, used for stable article identity.
pub fn fnv1a_hex(data: &[u8]) -> String {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in data {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}
