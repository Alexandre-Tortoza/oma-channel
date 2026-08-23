use anyhow::Context;

use crate::feed::https_only;
use crate::model::{OpmlImportOutput, Subscription};

/// Parse an OPML 2.0 (or 1.x) document into feed subscriptions.
/// Folder outlines become the category of nested feeds.
pub fn import(xml: &str) -> anyhow::Result<OpmlImportOutput> {
    let document =
        opml::OPML::from_str(xml).with_context(|| "malformed OPML document".to_string())?;

    let mut feeds = Vec::new();
    let mut invalid = 0usize;
    let mut total = 0usize;

    for outline in &document.body.outlines {
        walk_outline(outline, None, &mut feeds, &mut invalid, &mut total);
    }

    Ok(OpmlImportOutput {
        feeds,
        total_found: total,
        invalid,
    })
}

fn walk_outline(
    outline: &opml::Outline,
    category: Option<String>,
    feeds: &mut Vec<Subscription>,
    invalid: &mut usize,
    total: &mut usize,
) {
    match (&outline.xml_url, &outline.r#type) {
        (Some(xml_url), Some(t)) if t == "rss" || t == "atom" => {
            *total += 1;
            let url = decode_xml_entities(xml_url);
            if https_only(&url).is_err() {
                *invalid += 1;
                return;
            }
            let raw_title = if outline.text.trim().is_empty() {
                outline.title.as_deref().unwrap_or("")
            } else {
                outline.text.as_str()
            };
            let title = {
                let decoded = decode_xml_entities(raw_title);
                let trimmed = decoded.trim();
                if trimmed.is_empty() {
                    None
                } else {
                    Some(trimmed.to_string())
                }
            };
            feeds.push(Subscription {
                url,
                title,
                category: category.clone(),
                enabled: true,
            });
        }
        _ if !outline.outlines.is_empty() => {
            let child_category = if outline.text.trim().is_empty() {
                category.clone()
            } else {
                Some(outline.text.clone())
            };
            for child in &outline.outlines {
                walk_outline(child, child_category.clone(), feeds, invalid, total);
            }
        }
        _ => {}
    }
}

/// Export subscriptions as OPML 2.0, grouped by category folders.
pub fn export(subs: &[Subscription]) -> String {
    let mut out = String::new();
    out.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    out.push_str("<opml version=\"2.0\">\n");
    out.push_str("  <head>\n");
    out.push_str("    <title>Oma Channel subscriptions</title>\n");
    out.push_str("  </head>\n");
    out.push_str("  <body>\n");

    let mut folders: Vec<(String, Vec<&Subscription>)> = Vec::new();
    let mut loose: Vec<&Subscription> = Vec::new();
    for sub in subs {
        match sub.category.as_deref().filter(|c| !c.trim().is_empty()) {
            Some(category) => match folders.iter_mut().find(|(name, _)| name == category) {
                Some((_, list)) => list.push(sub),
                None => folders.push((category.to_string(), vec![sub])),
            },
            None => loose.push(sub),
        }
    }

    for sub in &loose {
        push_outline(&mut out, sub, 2);
    }
    for (name, subs) in &folders {
        let indent = "  ".repeat(2);
        out.push_str(&format!(
            "{indent}<outline text=\"{}\" title=\"{}\">\n",
            xml_escape(name),
            xml_escape(name)
        ));
        for sub in subs {
            push_outline(&mut out, sub, 3);
        }
        out.push_str(&format!("{indent}</outline>\n"));
    }

    out.push_str("  </body>\n");
    out.push_str("</opml>\n");
    out
}

fn push_outline(out: &mut String, sub: &Subscription, depth: usize) {
    let title = sub
        .title
        .clone()
        .unwrap_or_else(|| sub.url.clone());
    let indent = "  ".repeat(depth);
    out.push_str(&format!(
        "{indent}<outline type=\"rss\" text=\"{}\" title=\"{}\" xmlUrl=\"{}\" htmlUrl=\"{}\" />\n",
        xml_escape(&title),
        xml_escape(&title),
        xml_escape(&sub.url),
        xml_escape(&sub.url),
    ));
}

pub fn write_export(path: &std::path::Path, subs: &[Subscription]) -> anyhow::Result<usize> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    let xml = export(subs);
    std::fs::write(path, xml).with_context(|| format!("cannot write {}", path.display()))?;
    Ok(subs.len())
}

pub fn xml_escape(input: &str) -> String {
    input
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

fn decode_xml_entities(input: &str) -> String {
    input
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
}
