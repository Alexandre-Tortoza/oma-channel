use std::io::Read;
use std::time::Duration;

use anyhow::{bail, Context};

use crate::model::{fnv1a_hex, Article, Subscription};

const MAX_FEED_BYTES: u64 = 2 * 1024 * 1024;
const FETCH_TIMEOUT: Duration = Duration::from_secs(15);

pub fn https_only(url: &str) -> anyhow::Result<()> {
    let parsed = url::Url::parse(url).context("invalid feed URL")?;
    if parsed.scheme() != "https" {
        bail!("only https:// feeds are allowed");
    }
    Ok(())
}

/// Fetch and parse a single feed. Returns its articles (unsorted).
pub fn fetch_one(agent: &ureq::Agent, sub: &Subscription) -> anyhow::Result<Vec<Article>> {
    https_only(&sub.url)?;

    let response = agent
        .get(&sub.url)
        .call()
        .map_err(|e| anyhow::anyhow!(strip_ureq(&e)))?;

    let mut reader = response
        .into_reader()
        .take(MAX_FEED_BYTES.saturating_add(1));
    let mut body = Vec::new();
    reader.read_to_end(&mut body).context("download interrupted")?;
    if body.len() as u64 > MAX_FEED_BYTES {
        bail!("feed exceeds size limit");
    }

    parse_feed(&body, sub)
}

/// Parse a raw RSS/Atom payload into articles for the given subscription.
pub fn parse_feed(body: &[u8], sub: &Subscription) -> anyhow::Result<Vec<Article>> {
    let parser = feed_rs::parser::Builder::new()
        .base_uri(Some(sub.url.as_str()))
        .build();
    let feed = parser
        .parse(body)
        .context("malformed RSS/Atom payload")?;

    let feed_title = feed
        .title
        .map(|t| t.content)
        .or_else(|| sub.title.clone())
        .unwrap_or_else(|| sub.url.clone());
    let now = now_secs();

    let articles = feed
        .entries
        .iter()
        .filter_map(|entry| {
            let link = entry
                .links
                .first()
                .map(|l| l.href.clone())
                .unwrap_or_else(|| entry.id.clone());
            if link.is_empty() {
                return None;
            }
            let title = entry
                .title
                .as_ref()
                .map(|t| clean_text(&t.content))
                .filter(|t| !t.is_empty())
                .unwrap_or_else(|| "(sem título)".to_string());
            let summary = entry
                .summary
                .as_ref()
                .map(|s| snippet(&s.content, 280))
                .unwrap_or_default();
            let published = entry
                .published
                .map(|d| d.timestamp())
                .unwrap_or(entry.updated.map(|d| d.timestamp()).unwrap_or(0));
            let identity_source = format!("{}\u{0}{}", link, title);
            Some(Article {
                id: fnv1a_hex(identity_source.as_bytes()),
                feed_url: sub.url.clone(),
                feed_title: feed_title.clone(),
                category: sub.category.clone(),
                title,
                link,
                summary,
                published,
                fetched_at: now,
                read: false,
                bookmarked: false,
                bookmarked_at: 0,
                image_url: candidate_image_url(entry),
                artwork_path: None,
                artwork_failed: false,
            })
        })
        .collect();

    Ok(articles)
}

/// Picks a feed-declared artwork candidate for an entry, checked in order of
/// how deliberately the publisher put it there: an explicit media:thumbnail,
/// then a media:content/enclosure element whose declared type is an image.
/// This never downloads or validates anything — it just records a URL for
/// `enrich-artwork` to fetch and MIME-sniff later.
fn candidate_image_url(entry: &feed_rs::model::Entry) -> Option<String> {
    for media in &entry.media {
        if let Some(thumb) = media.thumbnails.first() {
            if !thumb.image.uri.is_empty() {
                return Some(thumb.image.uri.clone());
            }
        }
    }
    for media in &entry.media {
        for content in &media.content {
            let is_image = content
                .content_type
                .as_ref()
                .map(|ct| ct.to_string().starts_with("image/"))
                .unwrap_or(false);
            if is_image {
                if let Some(url) = &content.url {
                    return Some(url.to_string());
                }
            }
        }
    }
    for link in &entry.links {
        let is_enclosure = link.rel.as_deref() == Some("enclosure");
        let looks_image = link
            .media_type
            .as_deref()
            .map(|t| t.starts_with("image/"))
            .unwrap_or(false);
        if is_enclosure && looks_image {
            return Some(link.href.clone());
        }
    }
    None
}

/// Fetch all subscriptions in parallel; returns (url, Result) pairs.
pub fn fetch_all(
    subs: &[Subscription],
    concurrency: usize,
) -> Vec<(String, anyhow::Result<Vec<Article>>)> {
    let agent = build_agent();
    let worker_count = subs.len().min(concurrency.max(1));
    let chunks: Vec<Vec<Subscription>> = if worker_count <= 1 {
        vec![subs.to_vec()]
    } else {
        let per_chunk = subs.len().div_ceil(worker_count);
        subs.chunks(per_chunk).map(<[Subscription]>::to_vec).collect()
    };

    std::thread::scope(|scope| {
        let handles: Vec<_> = chunks
            .into_iter()
            .map(|chunk| {
                let agent = agent.clone();
                scope.spawn(move || {
                    chunk
                        .into_iter()
                        .map(|sub| {
                            let result = fetch_one(&agent, &sub);
                            (sub.url, result)
                        })
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        handles
            .into_iter()
            .flat_map(|h| h.join().expect("fetch worker panicked"))
            .collect()
    })
}

fn build_agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout(FETCH_TIMEOUT)
        .redirects(5)
        .user_agent(concat!("oma-channel/", env!("CARGO_PKG_VERSION")))
        .build()
}

fn strip_ureq(e: &ureq::Error) -> String {
    match e {
        ureq::Error::Status(code, _) => format!("HTTP {code}"),
        other => other.to_string(),
    }
}

pub fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Strip HTML tags and decode the common XML/HTML entities.
pub fn clean_text(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut inside_tag = false;
    for c in input.chars() {
        if c == '<' {
            inside_tag = true;
        } else if c == '>' {
            inside_tag = false;
        } else if !inside_tag {
            out.push(c);
        }
    }
    let decoded = html_escape::decode_html_entities(&out);
    decoded.split_whitespace().collect::<Vec<_>>().join(" ")
}

pub fn snippet(html: &str, max_chars: usize) -> String {
    let text = clean_text(html);
    if text.chars().count() <= max_chars {
        return text;
    }
    let truncated: String = text.chars().take(max_chars).collect();
    format!("{}…", truncated.trim_end())
}
