function barSection(value) {
  var name = String(value || "").trim().toLowerCase()
  if (name === "left" || name === "center" || name === "right") return name
  return "right"
}

function sectionFromLayout(layout, id) {
  var key = String(id || "")
  var sections = ["left", "center", "right"]
  if (!layout) return ""
  for (var s = 0; s < sections.length; s++) {
    var entries = layout[sections[s]] || []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var entryId = entry && typeof entry === "object" ? entry.id : entry
      if (String(entryId || "") === key) return sections[s]
    }
  }
  return ""
}

function entryFromLayout(layout, ids) {
  var idList = Array.isArray(ids) ? ids : [ids]
  var sections = ["left", "center", "right"]
  if (!layout) return null
  for (var s = 0; s < sections.length; s++) {
    var entries = layout[sections[s]] || []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (entry && typeof entry === "object") {
        for (var k = 0; k < idList.length; k++) {
          if (String(entry.id || "") === String(idList[k] || "")) return entry
        }
      }
    }
  }
  return null
}

function pollIntervalMinutes(value) {
  var n = Number(value)
  if (value === undefined || value === null || value === "" || !isFinite(n)) return 15
  if (n < 5) return 5
  return n
}

function maxItemsPerFeed(value) {
  var n = Number(value)
  if (value === undefined || value === null || value === "" || !isFinite(n)) return 10
  if (n < 1) return 1
  return Math.floor(n)
}

function isHttpsUrl(url) {
  var value = String(url || "").trim()
  if (!value) return false
  if (/\s/.test(value)) return false
  return /^https:\/\/[^\/?#\s]+/i.test(value)
}

function httpsFeedUrls(value) {
  var list = feedUrls(value)
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (isHttpsUrl(list[i])) out.push(list[i])
  }
  return out
}

function feedUrls(value) {
  if (value === undefined || value === null) return []
  if (typeof value !== "string" && value.length !== undefined && typeof value !== "function") {
    var fromList = []
    for (var i = 0; i < value.length; i++) {
      var item = String(value[i] || "").trim()
      if (item) fromList.push(item)
    }
    if (fromList.length) return fromList
  }
  var text = String(value)
  var lines = text.split(/\r?\n/)
  var urls = []
  for (var j = 0; j < lines.length; j++) {
    var line = lines[j].trim()
    if (line.length > 0) urls.push(line)
  }
  return urls
}

function emptyPanelCopy(urls) {
  if (!urls || urls.length === 0) return "Add feed URLs in Settings."
  return "No recent items"
}

function normalizeRetentionDays(value, fallback) {
  var fb = 30
  if (fallback !== undefined && fallback !== null && fallback !== "") {
    var fbNum = Number(fallback)
    if (isFinite(fbNum) && fbNum >= 1 && fbNum <= 3650 && Math.floor(fbNum) === fbNum) {
      fb = Math.floor(fbNum)
    }
  }

  if (value === undefined || value === null) return fb
  if (typeof value === "boolean") return fb
  var s = String(value).trim()
  if (!s || !/^[0-9]+$/.test(s)) return fb

  var n = Number(s)
  if (!isFinite(n) || isNaN(n)) return fb
  if (n < 1 || n > 3650) return fb
  return Math.floor(n)
}

function pageSize(value) {
  var n = Number(value)
  if (value === undefined || value === null || value === "" || !isFinite(n)) return 10
  if (n < 1) return 1
  if (n > 100) return 100
  return Math.floor(n)
}

function serializeFeedUrls(urls) {
  var list = urls || []
  var lines = []
  for (var i = 0; i < list.length; i++) {
    var line = String(list[i] || "").trim()
    if (line) lines.push(line)
  }
  return lines.join("\n")
}

function filePathFromUrl(urlOrPath) {
  var raw = String(urlOrPath || "").trim()
  if (!raw) return ""
  if (/^file:\/\//i.test(raw)) {
    var pathOnly = raw.replace(/^file:\/\/(localhost)?/i, "")
    try {
      return decodeURIComponent(pathOnly)
    } catch (e) {
      return pathOnly
    }
  }
  return raw
}

function filenameFromPath(filePath) {
  var raw = String(filePath || "").trim()
  if (!raw) return ""
  return raw.replace(/^.*[\\\/]/, "")
}

function extractDomainTitle(url) {
  var str = String(url || "").trim()
  if (!str) return ""
  try {
    var match = /^https?:\/\/([^\/?#]+)/i.exec(str)
    if (match && match[1]) {
      return match[1].replace(/^www\./i, "")
    }
  } catch (e) {}
  return str
}

function normalizeSubscriptions(rawSubscriptions, rawFeedUrls) {
  var subs = []
  if (typeof rawSubscriptions === "string") {
    var trimmed = rawSubscriptions.trim()
    if (trimmed.indexOf("[") === 0) {
      try {
        var parsed = JSON.parse(trimmed)
        if (Array.isArray(parsed)) subs = parsed
      } catch (e) {}
    }
  } else if (Array.isArray(rawSubscriptions)) {
    subs = rawSubscriptions.slice()
  }

  var existingMap = {}
  var out = []
  for (var i = 0; i < subs.length; i++) {
    var s = subs[i]
    if (s && typeof s === "object" && isHttpsUrl(s.url)) {
      var u = String(s.url || "").trim()
      if (!existingMap[u]) {
        var catPath = Array.isArray(s.categoryPath)
          ? s.categoryPath.map(function(c) { return String(c || "").trim() }).filter(Boolean)
          : (s.category ? [String(s.category).trim()] : [])
        var normSub = {
          url: u,
          title: String(s.title || extractDomainTitle(u)).trim() || extractDomainTitle(u),
          categoryPath: catPath,
          category: catPath.length ? catPath[catPath.length - 1] : "",
          enabled: s.enabled !== false
        }
        existingMap[u] = normSub
        out.push(normSub)
      }
    } else if (typeof s === "string" && isHttpsUrl(s)) {
      var uStr = s.trim()
      if (!existingMap[uStr]) {
        var plainSub = {
          url: uStr,
          title: extractDomainTitle(uStr),
          categoryPath: [],
          category: "",
          enabled: true
        }
        existingMap[uStr] = plainSub
        out.push(plainSub)
      }
    }
  }

  // Migration from legacy rawFeedUrls
  var fallbackUrls = httpsFeedUrls(rawFeedUrls)
  for (var j = 0; j < fallbackUrls.length; j++) {
    var url = fallbackUrls[j]
    if (!existingMap[url]) {
      var newSub = {
        url: url,
        title: extractDomainTitle(url),
        categoryPath: [],
        category: "",
        enabled: true
      }
      existingMap[url] = newSub
      out.push(newSub)
    }
  }

  return out
}

function serializeSubscriptions(subscriptions) {
  return JSON.stringify(normalizeSubscriptions(subscriptions))
}

function mergeSubscriptions(current, incoming) {
  var existing = normalizeSubscriptions(current)
  var inc = normalizeSubscriptions(incoming)
  var map = {}
  var out = []
  for (var i = 0; i < existing.length; i++) {
    map[existing[i].url] = existing[i]
    out.push(existing[i])
  }
  for (var j = 0; j < inc.length; j++) {
    var s = inc[j]
    if (!map[s.url]) {
      map[s.url] = s
      out.push(s)
    } else {
      if ((!map[s.url].categoryPath || !map[s.url].categoryPath.length) && s.categoryPath && s.categoryPath.length) {
        map[s.url].categoryPath = s.categoryPath
        map[s.url].category = s.category
      }
      if (s.title && s.title !== s.url && (!map[s.url].title || map[s.url].title === map[s.url].url)) {
        map[s.url].title = s.title
      }
    }
  }
  return out
}

function normalizeFeedInputUrl(input) {
  var s = String(input || "").trim()
  if (!s) return ""
  if (s.indexOf("://") === -1) {
    s = "https://" + s
  }
  return s
}

function getAvailableCategories(subscriptions) {
  var subs = normalizeSubscriptions(subscriptions)
  var map = {}
  var out = []

  for (var i = 0; i < subs.length; i++) {
    var sub = subs[i]
    var cat = String(sub.category || "").trim()
    var path = Array.isArray(sub.categoryPath) ? sub.categoryPath : []
    var display = path.length > 1 ? path.join(" / ") : cat

    if (display && !map[display.toLowerCase()]) {
      map[display.toLowerCase()] = true
      out.push({
        id: cat || display,
        name: cat || display,
        display: display,
        category: cat || display,
        categoryPath: path.length ? path : [cat || display]
      })
    }
  }

  out.sort(function(a, b) {
    return a.display.toLowerCase().localeCompare(b.display.toLowerCase())
  })

  return out
}

function normalizeCategorySelection(inputCategory, subscriptions) {
  var raw = String(inputCategory || "").trim()
  if (!raw || raw.toLowerCase() === "no category" || raw.toLowerCase() === "none") {
    return { category: "", categoryPath: [] }
  }

  var subs = normalizeSubscriptions(subscriptions)
  // Check against existing subscriptions case-insensitively
  for (var i = 0; i < subs.length; i++) {
    var s = subs[i]
    var cat = String(s.category || "").trim()
    var path = Array.isArray(s.categoryPath) ? s.categoryPath : []
    var pathStr = path.join(" / ").trim()

    if (pathStr && pathStr.toLowerCase() === raw.toLowerCase()) {
      return { category: cat || path[path.length - 1], categoryPath: path }
    }
    if (cat && cat.toLowerCase() === raw.toLowerCase()) {
      return { category: cat, categoryPath: path.length ? path : [cat] }
    }
  }

  // If user typed a new path with " / "
  if (raw.indexOf("/") !== -1) {
    var parts = raw.split(/\s*\/\s*/).map(function(p) { return p.trim() }).filter(Boolean)
    if (parts.length > 0) {
      return { category: parts[parts.length - 1], categoryPath: parts }
    }
  }

  return { category: raw, categoryPath: [raw] }
}

function addSubscription(subscriptions, inputUrl, inputTitle, inputCategory) {
  var url = normalizeFeedInputUrl(inputUrl)
  if (!isHttpsUrl(url)) {
    return { ok: false, error: "Please enter a valid HTTPS feed URL", subscriptions: normalizeSubscriptions(subscriptions) }
  }

  var list = normalizeSubscriptions(subscriptions)
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].url || "").trim().toLowerCase() === url.toLowerCase()) {
      return { ok: false, error: "Already subscribed", subscriptions: list }
    }
  }

  var title = String(inputTitle || "").trim() || extractDomainTitle(url)
  var catInfo = normalizeCategorySelection(inputCategory, list)

  var newSub = {
    url: url,
    title: title,
    categoryPath: catInfo.categoryPath,
    category: catInfo.category,
    enabled: true
  }

  var next = [newSub].concat(list)
  return { ok: true, newSub: newSub, subscriptions: next }
}

function removeSubscription(subscriptions, targetUrl) {
  var url = String(targetUrl || "").trim().toLowerCase()
  var list = normalizeSubscriptions(subscriptions)
  var next = []
  var removed = null
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].url || "").trim().toLowerCase() === url) {
      removed = list[i]
    } else {
      next.push(list[i])
    }
  }
  return { ok: removed !== null, removed: removed, subscriptions: next }
}

function calculateImportResult(currentSubs, parsedResult, filename) {
  var current = normalizeSubscriptions(currentSubs)
  var incoming = []
  var invalidCount = 0
  var parsedCategories = []

  if (parsedResult && typeof parsedResult === "object") {
    if (parsedResult.subscriptions && Array.isArray(parsedResult.subscriptions)) {
      incoming = normalizeSubscriptions(parsedResult.subscriptions)
    } else if (parsedResult.feeds && Array.isArray(parsedResult.feeds)) {
      incoming = normalizeSubscriptions(parsedResult.feeds)
    } else {
      incoming = normalizeSubscriptions(parsedResult)
    }
    invalidCount = typeof parsedResult.invalidCount === "number" ? parsedResult.invalidCount : 0
    if (Array.isArray(parsedResult.categories)) parsedCategories = parsedResult.categories
  } else {
    incoming = normalizeSubscriptions(parsedResult)
  }

  var currentUrls = {}
  for (var i = 0; i < current.length; i++) currentUrls[current[i].url] = true

  var added = []
  var duplicates = 0
  for (var j = 0; j < incoming.length; j++) {
    if (!currentUrls[incoming[j].url]) {
      added.push(incoming[j])
      currentUrls[incoming[j].url] = true
    } else {
      duplicates++
    }
  }

  var nameLabel = filename ? (" from " + filename) : ""
  var parts = []
  if (added.length > 0) {
    parts.push("Imported " + added.length + " feed" + (added.length === 1 ? "" : "s") + nameLabel)
  } else if (duplicates > 0) {
    parts.push("All " + duplicates + " feed" + (duplicates === 1 ? "" : "s") + nameLabel + " already added")
  } else {
    parts.push("No valid feeds found" + nameLabel)
  }
  if (duplicates > 0 && added.length > 0) {
    parts.push(duplicates + " duplicate" + (duplicates === 1 ? "" : "s"))
  }
  if (invalidCount > 0) {
    parts.push(invalidCount + " need attention")
  }
  var message = parts.join(" · ")
  var nextSubs = mergeSubscriptions(current, added)
  var nextFeeds = []
  for (var k = 0; k < nextSubs.length; k++) nextFeeds.push(nextSubs[k].url)

  return {
    status: (added.length > 0 || duplicates > 0) ? "success" : "error",
    imported: added.length,
    duplicates: duplicates,
    invalid: invalidCount,
    message: message,
    newSubscriptions: nextSubs,
    newFeeds: nextFeeds,
    categories: parsedCategories
  }
}

function matchCategory(article, selectedCategory) {
  if (!selectedCategory || String(selectedCategory).trim().toLowerCase() === "all") return true
  if (!article) return false
  var target = String(selectedCategory).trim().toLowerCase()

  var cat = String(article.category || "").trim().toLowerCase()
  if (cat && cat === target) return true

  var path = article.categoryPath
  if (Array.isArray(path)) {
    for (var i = 0; i < path.length; i++) {
      if (String(path[i] || "").trim().toLowerCase() === target) return true
    }
  }

  return false
}

function enrichArticles(articles, subscriptions) {
  var list = articles || []
  var subs = normalizeSubscriptions(subscriptions)
  var subMap = {}
  for (var s = 0; s < subs.length; s++) {
    subMap[subs[s].url] = subs[s]
  }

  var out = []
  for (var i = 0; i < list.length; i++) {
    var a = list[i]
    if (!a) continue
    var feedUrl = String(a.feedUrl || a.subscriptionUrl || "").trim()
    var sub = feedUrl ? subMap[feedUrl] : null
    var cat = a.category || (sub ? sub.category : "") || ""
    var catPath = (a.categoryPath && a.categoryPath.length)
      ? a.categoryPath
      : ((sub && sub.categoryPath && sub.categoryPath.length) ? sub.categoryPath : (cat ? [cat] : []))
    var feedName = a.feedName || (sub ? sub.title : "") || extractDomainTitle(feedUrl || a.link)

    out.push({
      id: a.id || a.identity || a.link || "",
      identity: a.identity || a.link || "",
      link: a.link || "",
      title: a.title || "",
      excerpt: a.excerpt || "",
      feedName: feedName,
      feedTitle: feedName,
      feedUrl: feedUrl || (sub ? sub.url : ""),
      subscriptionUrl: feedUrl || (sub ? sub.url : ""),
      category: cat,
      categoryPath: catPath,
      pubDateMs: a.pubDateMs,
      bookmarked: a.bookmarked === true,
      bookmarkedAtMs: Number(a.bookmarkedAtMs) || 0,
      artworkPath: a.artworkPath ? String(a.artworkPath) : ""
    })
  }

  return out
}

function extractCategories(subscriptions, articles, readSet) {
  var subs = normalizeSubscriptions(subscriptions)
  var arts = enrichArticles(articles, subs)
  var reads = readSet || []

  var totalCount = arts.length
  var totalUnread = unreadCount(arts, reads)

  var catMap = {}
  for (var i = 0; i < subs.length; i++) {
    var sub = subs[i]
    if (sub.category && !catMap[sub.category]) {
      catMap[sub.category] = true
    }
    if (Array.isArray(sub.categoryPath)) {
      for (var p = 0; p < sub.categoryPath.length; p++) {
        var pName = String(sub.categoryPath[p] || "").trim()
        if (pName && !catMap[pName]) catMap[pName] = true
      }
    }
  }

  var catNames = Object.keys(catMap).sort()
  var list = [
    { id: "all", name: "All", count: totalCount, unreadCount: totalUnread }
  ]

  for (var k = 0; k < catNames.length; k++) {
    var name = catNames[k]
    var catArticles = []
    var catUnread = 0
    for (var a = 0; a < arts.length; a++) {
      var item = arts[a]
      if (matchCategory(item, name)) {
        catArticles.push(item)
        if (!isRead(reads, item)) catUnread++
      }
    }
    list.push({
      id: name,
      name: name,
      count: catArticles.length,
      unreadCount: catUnread
    })
  }

  return list
}

function filterReaderArticles(articles, options) {
  var opts = options || {}
  var category = String(opts.category || "all").trim()
  var unreadOnly = Boolean(opts.unreadOnly)
  var bookmarkedOnly = Boolean(opts.bookmarkedOnly)
  var search = String(opts.search || "").trim().toLowerCase()
  var readSet = opts.readSet || []
  var list = enrichArticles(articles, opts.subscriptions)

  var out = []
  for (var i = 0; i < list.length; i++) {
    var item = list[i] || {}

    // 1. Category Matching
    if (!matchCategory(item, category)) {
      continue
    }

    // 2. Unread Check
    if (unreadOnly && isRead(readSet, item)) {
      continue
    }

    // 2b. Saved/bookmarked check
    if (bookmarkedOnly && !item.bookmarked) {
      continue
    }

    // 3. Search Query Check
    if (search) {
      var catStr = Array.isArray(item.categoryPath) ? item.categoryPath.join(" ") : (item.category || "")
      var hay = [item.title, item.excerpt, item.feedName, item.feedTitle, catStr, item.link, item.feedUrl].join(" ").toLowerCase()
      if (hay.indexOf(search) === -1) {
        continue
      }
    }

    out.push(item)
  }

  return out
}

function activateUrl(item) {
  if (!item) return ""
  var link = String(item.link || "").trim()
  return isHttpsUrl(link) ? link : ""
}

function itemIdentity(item) {
  if (!item) return ""
  if (typeof item === "string") return item.trim()
  return String(item.identity || item.guid || item.id || item.link || "").trim()
}

function isRead(readSet, item) {
  var id = itemIdentity(item)
  if (!id) return false
  var list = readSet || []
  for (var i = 0; i < list.length; i++) {
    if (String(list[i]).trim() === id) return true
  }
  return false
}

function unreadCount(items, readSet) {
  return tabItems(items, readSet, "new").length
}

function tabItems(items, readSet, tab) {
  var list = items || []
  var wantRead = tab === "read"
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (isRead(readSet, list[i]) === wantRead) out.push(list[i])
  }
  return out
}

function relativeTime(pubDateMs, nowMs) {
  if (pubDateMs == null || !isFinite(pubDateMs)) return ""
  var now = nowMs != null ? nowMs : Date.now()
  var delta = now - pubDateMs
  if (!isFinite(delta) || delta < 0) return ""
  var minutes = Math.floor(delta / 60000)
  if (minutes < 1) return "just now"
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  var days = Math.floor(hours / 24)
  return days + "d"
}

// ---- Rust backend adapter -------------------------------------------------
// Articles come from the oma-channel binary as JSON (camelCase) and are
// adapted here to the shape the QML views expect.

function adaptRustItems(raw) {
  var out = []
  var list = raw || []
  for (var i = 0; i < list.length; i++) {
    var it = list[i]
    if (!it || !it.id) continue
    var cat = String(it.category || "")
    out.push({
      id: String(it.id),
      identity: String(it.id),
      title: String(it.title || "Untitled"),
      link: String(it.link || ""),
      summary: String(it.summary || ""),
      pubDateMs: (Number(it.published) || 0) * 1000,
      fetchedAtMs: (Number(it.fetchedAt) || 0) * 1000,
      feedUrl: String(it.feedUrl || ""),
      subscriptionUrl: String(it.feedUrl || ""),
      feedName: String(it.feedTitle || ""),
      feedTitle: String(it.feedTitle || ""),
      category: cat,
      categoryPath: cat ? [cat] : [],
      read: it.read === true,
      bookmarked: it.bookmarked === true,
      bookmarkedAtMs: (Number(it.bookmarkedAt) || 0) * 1000,
      artworkPath: it.artworkPath ? String(it.artworkPath) : ""
    })
  }
  return out
}

function collectReadIds(items) {
  var ids = []
  var list = items || []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].id && list[i].read === true) ids.push(String(list[i].id))
  }
  return ids
}

function setItemsRead(items, ids, read) {
  var wanted = {}
  var idList = ids || []
  for (var i = 0; i < idList.length; i++) if (idList[i]) wanted[idList[i]] = true
  var out = []
  var source = items || []
  for (var j = 0; j < source.length; j++) {
    var a = source[j]
    if (a && a.id && wanted[a.id]) {
      var copy = {}
      for (var k in a) copy[k] = a[k]
      copy.read = read === true
      out.push(copy)
    } else {
      out.push(a)
    }
  }
  return out
}

function setItemsBookmarked(items, ids, bookmarked, nowMs) {
  var wanted = {}
  var idList = ids || []
  for (var i = 0; i < idList.length; i++) if (idList[i]) wanted[idList[i]] = true
  var now = (typeof nowMs === "number" && isFinite(nowMs) && nowMs > 0) ? nowMs : Date.now()
  var out = []
  var source = items || []
  for (var j = 0; j < source.length; j++) {
    var a = source[j]
    if (a && a.id && wanted[a.id]) {
      var copy = {}
      for (var k in a) copy[k] = a[k]
      copy.bookmarked = bookmarked === true
      copy.bookmarkedAtMs = bookmarked === true ? now : 0
      out.push(copy)
    } else {
      out.push(a)
    }
  }
  return out
}
