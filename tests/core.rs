use oma_channel::feed::{clean_text, https_only, parse_feed, snippet};
use oma_channel::model::{Subscription, State};
use oma_channel::opml_io;
use oma_channel::state::merge_fetch;

fn sub(url: &str) -> Subscription {
    Subscription {
        url: url.to_string(),
        title: None,
        category: None,
        enabled: true,
    }
}

fn fixture(name: &str) -> Vec<u8> {
    std::fs::read(format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"))).unwrap()
}

#[test]
fn rejects_non_https_urls() {
    assert!(https_only("http://inseguro.example/feed").is_err());
    assert!(https_only("ftp://x.example/feed").is_err());
    assert!(https_only("https://ok.example/feed.xml").is_ok());
}

#[test]
fn parses_rss2_fixture() {
    let s = sub("https://blogsolto.example/feed.xml");
    let articles = parse_feed(&fixture("feed-rss.xml"), &s).unwrap();
    assert_eq!(articles.len(), 2);
    let first = articles.iter().find(|a| a.title.contains("Primeiro")).unwrap();
    assert_eq!(first.link, "https://blogsolto.example/posts/primeiro");
    assert_eq!(first.feed_title, "Blog Solto");
    // HTML tags stripped and entities decoded
    assert_eq!(first.summary, "Olá mundo, este é o primeiro post.");
    assert!(first.published > 0);
    assert!(!first.id.is_empty());
}

#[test]
fn parses_atom_fixture() {
    let s = sub("https://blog.rust-lang.org/feed.xml");
    let articles = parse_feed(&fixture("feed-atom.xml"), &s).unwrap();
    assert_eq!(articles.len(), 2);
    let announce = articles
        .iter()
        .find(|a| a.title.contains("Announcing"))
        .unwrap();
    assert_eq!(
        announce.link,
        "https://blog.rust-lang.org/2026/08/20/Rust-1.97.0/"
    );
    assert_eq!(announce.feed_title, "Rust Blog");
}

#[test]
fn parses_media_thumbnail_as_image_candidate() {
    let s = sub("https://fotos.example/feed.xml");
    let articles = parse_feed(&fixture("feed-with-media-thumbnail.xml"), &s).unwrap();
    assert_eq!(articles.len(), 1);
    assert_eq!(
        articles[0].image_url.as_deref(),
        Some("https://fotos.example/img/thumb.jpg")
    );
}

#[test]
fn parses_image_enclosure_as_image_candidate() {
    let s = sub("https://postais.example/feed.xml");
    let articles = parse_feed(&fixture("feed-with-enclosure.xml"), &s).unwrap();
    assert_eq!(articles.len(), 2);
    let with_image = articles.iter().find(|a| a.title.contains("Com enclosure")).unwrap();
    assert_eq!(with_image.image_url.as_deref(), Some("https://postais.example/img/cover.png"));
    let without_image = articles.iter().find(|a| a.title.contains("Sem imagem")).unwrap();
    assert!(without_image.image_url.is_none());
}

#[test]
fn opml_import_extracts_feeds_and_categories() {
    let xml = String::from_utf8(fixture("subscriptions.opml")).unwrap();
    let out = opml_io::import(&xml).unwrap();
    assert_eq!(out.total_found, 4);
    assert_eq!(out.invalid, 1); // the http:// feed is rejected
    assert_eq!(out.feeds.len(), 3);

    let tech = out
        .feeds
        .iter()
        .find(|f| f.url == "https://blog.rust-lang.org/feed.xml")
        .unwrap();
    assert_eq!(tech.category.as_deref(), Some("Tecnologia"));
    assert_eq!(tech.title.as_deref(), Some("Rust Blog"));

    let loose = out
        .feeds
        .iter()
        .find(|f| f.url == "https://blogsolto.example/feed.xml")
        .unwrap();
    assert!(loose.category.is_none());
}

#[test]
fn opml_export_round_trip() {
    let subs = vec![
        Subscription {
            url: "https://a.example/feed".into(),
            title: Some("A & B <blog>".into()),
            category: None,
            enabled: true,
        },
        Subscription {
            url: "https://b.example/feed".into(),
            title: None,
            category: Some("Tech/News".into()),
            enabled: true,
        },
    ];
    let xml = opml_io::export(&subs);
    let re = opml_io::import(&xml).unwrap();
    assert_eq!(re.feeds.len(), 2);
    assert_eq!(re.invalid, 0);
    let b = re.feeds.iter().find(|f| f.url == "https://b.example/feed").unwrap();
    assert_eq!(b.category.as_deref(), Some("Tech/News"));
    let a = re.feeds.iter().find(|f| f.url == "https://a.example/feed").unwrap();
    assert_eq!(a.title.as_deref(), Some("A & B <blog>"));
}

fn article(id: &str, feed_url: &str, published: i64) -> oma_channel::model::Article {
    oma_channel::model::Article {
        id: id.to_string(),
        feed_url: feed_url.to_string(),
        feed_title: feed_url.to_string(),
        category: None,
        title: id.to_string(),
        link: format!("https://example.org/{id}"),
        summary: String::new(),
        published,
        fetched_at: published,
        read: false,
        bookmarked: false,
        bookmarked_at: 0,
        image_url: None,
        artwork_path: None,
        artwork_failed: false,
    }
}

#[test]
fn state_read_tracking() {
    let mut st = State::new();
    st.items = vec![article("a", "https://f1", 100), article("b", "https://f1", 200)];
    assert_eq!(st.unread_count(), 2);
    assert!(st.set_read("a", true));
    assert!(!st.set_read("a", true)); // idempotent
    assert!(st.is_read("a"));
    assert_eq!(st.unread_count(), 1);
    assert!(st.set_read("a", false));
    assert!(!st.is_read("a"));
}

#[test]
fn retention_prune_removes_old_articles() {
    let now = 10_000i64;
    let mut st = State::new();
    st.items = vec![
        article("fresh", "https://f1", now - 86_400),
        article("old", "https://f1", now - 90 * 86_400),
    ];
    let removed = st.prune_retention(30, now);
    assert_eq!(removed, 1);
    assert_eq!(st.items.len(), 1);
    assert_eq!(st.items[0].id, "fresh");
}

#[test]
fn merge_fetch_replaces_keeps_and_drops() {
    let mut st = State::new();
    st.items = vec![
        article("old-a", "https://a", 100),
        article("old-b", "https://b", 100),
        article("gone", "https://gone", 999),
    ];
    st.set_read("old-b", true);

    let fresh_a = vec![article("new-a2", "https://a", 300), article("new-a1", "https://a", 200)];
    merge_fetch(
        &mut st,
        vec![("https://a".into(), fresh_a)], // a fetched ok; b failed (absent)
        &["https://a", "https://b"],
        20,
        400,
    );

    let ids: Vec<&str> = st.items.iter().map(|a| a.id.as_str()).collect();
    assert!(ids.contains(&"new-a2") && ids.contains(&"new-a1"));
    assert!(ids.contains(&"old-b")); // kept because fetch failed
    assert!(!ids.contains(&"old-a")); // replaced by fresh fetch
    assert!(!ids.contains(&"gone")); // feed no longer subscribed
    assert_eq!(ids[0], "new-a2"); // sorted desc by date
    assert!(st.is_read("old-b")); // read flags survive
    assert_eq!(st.last_fetch, 400);
}

#[test]
fn max_per_feed_truncates() {
    let mut st = State::new();
    let fresh: Vec<oma_channel::model::Article> = (0..30)
        .map(|i| article(&format!("n{i}"), "https://a", i))
        .collect();
    merge_fetch(&mut st, vec![("https://a".into(), fresh)], &["https://a"], 5, 100);
    assert_eq!(st.items.len(), 5);
}

#[test]
fn set_bookmarked_toggles_and_stamps_time() {
    let mut st = State::new();
    st.items = vec![article("a", "https://f1", 100)];
    assert!(st.set_bookmarked("a", true, 500));
    assert!(!st.set_bookmarked("a", true, 600)); // idempotent
    assert!(st.items[0].bookmarked);
    assert_eq!(st.items[0].bookmarked_at, 500);
    assert_eq!(st.bookmarked_count(), 1);
    assert!(st.set_bookmarked("a", false, 700));
    assert!(!st.items[0].bookmarked);
    assert_eq!(st.items[0].bookmarked_at, 0);
    assert_eq!(st.bookmarked_count(), 0);
    assert!(!st.set_bookmarked("missing", true, 800)); // unknown id
}

#[test]
fn bookmark_survives_unsubscribe() {
    let mut st = State::new();
    st.items = vec![
        article("keep-a", "https://a", 100),
        article("saved-b", "https://b", 100),
    ];
    st.set_bookmarked("saved-b", true, 100);

    let fresh_a = vec![article("new-a", "https://a", 300)];
    // feed b is no longer enabled/subscribed at all
    merge_fetch(&mut st, vec![("https://a".into(), fresh_a)], &["https://a"], 20, 400);

    let saved = st.items.iter().find(|a| a.id == "saved-b").unwrap();
    assert!(saved.bookmarked);
    assert_eq!(saved.bookmarked_at, 100);
}

#[test]
fn bookmark_survives_per_feed_cap() {
    let mut st = State::new();
    st.items = vec![article("old-bookmarked", "https://a", 1)];
    st.set_bookmarked("old-bookmarked", true, 1);

    // 30 fresh, newer articles for the same feed with a cap of 5 — the
    // bookmarked article ranks below the cap on recency alone.
    let fresh: Vec<oma_channel::model::Article> = (0..30)
        .map(|i| article(&format!("n{i}"), "https://a", 1000 + i))
        .collect();
    merge_fetch(&mut st, vec![("https://a".into(), fresh)], &["https://a"], 5, 2000);

    assert_eq!(st.items.len(), 6); // 5 capped + 1 exempt bookmark
    let saved = st.items.iter().find(|a| a.id == "old-bookmarked").unwrap();
    assert!(saved.bookmarked);
}

#[test]
fn bookmark_survives_retention_prune() {
    let now = 10_000i64;
    let mut st = State::new();
    st.items = vec![
        article("fresh", "https://f1", now - 86_400),
        article("old-saved", "https://f1", now - 90 * 86_400),
    ];
    st.set_bookmarked("old-saved", true, now);
    let removed = st.prune_retention(30, now);
    assert_eq!(removed, 0);
    assert_eq!(st.items.len(), 2);
}

#[test]
fn text_cleaning() {
    assert_eq!(clean_text("<p>Hello &amp; <b>world</b></p>"), "Hello & world");
    let long = format!("<p>{}</p>", "x".repeat(500));
    assert_eq!(snippet(&long, 10), "xxxxxxxxxx…");
}
