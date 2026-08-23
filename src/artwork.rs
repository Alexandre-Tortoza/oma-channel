use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{anyhow, bail, Context};

use crate::model::fnv1a_hex;

const MAX_IMAGE_BYTES: u64 = 2 * 1024 * 1024;
const IMAGE_FETCH_TIMEOUT: Duration = Duration::from_secs(8);

pub fn cache_dir() -> anyhow::Result<PathBuf> {
    let base = dirs::cache_dir().context("cannot determine XDG cache directory")?;
    Ok(base.join("omarchy-oma-channel").join("artwork"))
}

fn build_agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout(IMAGE_FETCH_TIMEOUT)
        .redirects(5)
        .user_agent(concat!("oma-channel/", env!("CARGO_PKG_VERSION")))
        .build()
}

/// Downloads an image, bounded in size, and writes it to `dest_dir` under a
/// name derived from its own bytes (so the same picture referenced by two
/// articles downloads once and re-requesting it after a sweep lands on the
/// same path). The file's real type is sniffed from its bytes rather than
/// trusted from the URL or a server-supplied Content-Type, so an HTML error
/// page or a redirect to a login wall never ends up rendered as an image.
pub fn download_image(url: &str, dest_dir: &Path) -> anyhow::Result<PathBuf> {
    crate::feed::https_only(url)?;

    let agent = build_agent();
    let response = agent
        .get(url)
        .call()
        .map_err(|e| anyhow!(strip_ureq(&e)))?;

    let mut reader = response.into_reader().take(MAX_IMAGE_BYTES.saturating_add(1));
    let mut body = Vec::new();
    reader.read_to_end(&mut body).context("download interrupted")?;
    if body.len() as u64 > MAX_IMAGE_BYTES {
        bail!("image exceeds size limit");
    }
    if body.is_empty() {
        bail!("empty response");
    }

    let kind = infer::get(&body)
        .filter(|k| k.mime_type().starts_with("image/"))
        .ok_or_else(|| anyhow!("not a recognized image type"))?;

    fs::create_dir_all(dest_dir)
        .with_context(|| format!("cannot create {}", dest_dir.display()))?;
    let dest = dest_dir.join(format!("{}.{}", fnv1a_hex(&body), kind.extension()));
    fs::write(&dest, &body).with_context(|| format!("cannot write {}", dest.display()))?;
    Ok(dest)
}

/// Reads an article page looking for its OpenGraph lead image, bounded in
/// time and bytes, with no full HTML parser: the tag is almost always in the
/// first few KB of `<head>`, so a capped read plus a simple string scan is
/// enough and keeps this from pulling a heavy parser into a bar plugin.
pub fn fetch_og_image(article_url: &str) -> anyhow::Result<Option<String>> {
    crate::feed::https_only(article_url)?;
    const PAGE_MAX_BYTES: u64 = 512 * 1024;

    let agent = build_agent();
    let response = agent
        .get(article_url)
        .call()
        .map_err(|e| anyhow!(strip_ureq(&e)))?;
    let mut reader = response.into_reader().take(PAGE_MAX_BYTES);
    let mut body = Vec::new();
    reader.read_to_end(&mut body).context("download interrupted")?;
    let html = String::from_utf8_lossy(&body);
    Ok(extract_og_image(&html))
}

fn extract_og_image(html: &str) -> Option<String> {
    let flat = html.replace('\n', " ");
    let lower = flat.to_lowercase();
    let mut search_from = 0usize;
    while let Some(rel_start) = lower[search_from..].find("<meta") {
        let tag_start = search_from + rel_start;
        let tag_end = tag_start + flat[tag_start..].find('>')?;
        let tag = &flat[tag_start..=tag_end];
        let tag_lower = &lower[tag_start..=tag_end];
        // property="og:image" and name="og:image" are used interchangeably by
        // publishers, and attribute order isn't guaranteed either way, so a
        // simple substring check on the whole tag stands in for matching the
        // property/name attribute specifically.
        if tag_lower.contains("og:image") {
            if let Some(value) = extract_attr(tag, tag_lower, "content") {
                if !value.is_empty() {
                    return Some(value);
                }
            }
        }
        search_from = tag_end + 1;
    }
    None
}

fn extract_attr(tag: &str, tag_lower: &str, name: &str) -> Option<String> {
    let needle = format!("{name}=");
    let idx = tag_lower.find(&needle)?;
    let rest = &tag[idx + needle.len()..];
    let quote = rest.chars().next()?;
    if quote != '"' && quote != '\'' {
        return None;
    }
    let value_end = rest[1..].find(quote)?;
    Some(rest[1..1 + value_end].to_string())
}

/// Deletes cache files not referenced by `artwork_path` on any current
/// article. Ownership-based, not age-based: a bookmarked article's row (and
/// thus its artwork_path) already survives every prune/unsubscribe path in
/// state.rs, so its image is automatically exempt here too.
pub fn sweep_orphaned(state: &crate::model::State, dir: &Path) -> anyhow::Result<usize> {
    let referenced: std::collections::HashSet<&str> = state
        .items
        .iter()
        .filter_map(|a| a.artwork_path.as_deref())
        .collect();

    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(0),
        Err(e) => return Err(e).with_context(|| format!("cannot read {}", dir.display())),
    };

    let mut deleted = 0usize;
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let path_str = match path.to_str() {
            Some(s) => s,
            None => continue,
        };
        if !referenced.contains(path_str) && fs::remove_file(&path).is_ok() {
            deleted += 1;
        }
    }
    Ok(deleted)
}

fn strip_ureq(e: &ureq::Error) -> String {
    match e {
        ureq::Error::Status(code, _) => format!("HTTP {code}"),
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_og_image_from_meta_tag() {
        let html = r#"<html><head><meta property="og:image" content="https://x.example/pic.jpg"></head></html>"#;
        assert_eq!(extract_og_image(html).as_deref(), Some("https://x.example/pic.jpg"));
    }

    #[test]
    fn extracts_og_image_with_single_quotes_and_reversed_attrs() {
        let html = r#"<meta content='https://x.example/a.png' property='og:image'>"#;
        assert_eq!(extract_og_image(html).as_deref(), Some("https://x.example/a.png"));
    }

    #[test]
    fn missing_og_image_returns_none() {
        let html = r#"<html><head><title>No image here</title></head></html>"#;
        assert_eq!(extract_og_image(html), None);
    }
}
