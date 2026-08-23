import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Headless singleton (kind "service" in manifest.json). Owns every request to
// the oma-channel binary, the in-memory article cache, subscription and
// reading settings, and the IPC surface -- mirroring how omarchy.media splits
// a per-monitor BarWidget from a single shared Service.
//
// A bar surface is built once per monitor (see /usr/share/omarchy/shell's own
// Bar.qml comments), so a plugin that fetched and polled from inside its own
// BarWidget.qml -- as this one used to -- fetches once per monitor and runs
// that many concurrent copies of the backend against the same state file.
// Centralizing here fixes that as a side effect of also giving IPC and
// artwork enrichment a single place to live.
Item {
  id: root

  // Injected by shell.qml's ensureService() after createObject() returns.
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: ""

  readonly property string moduleId: "io.github.alexmrtr.oma-channel"

  // Pushed in by every live BarWidget instance's onSettingsChanged (all of
  // them see the same shell.json entry, since barWidget.allowMultiple is
  // false). configure() is idempotent so N monitors calling it with the same
  // value is a no-op past the first.
  property var settings: ({})
  property string _lastSettingsJson: ""
  // Guards against the startup race between the cache load (Component.onCompleted
  // below, which needs no settings) and the first settings push from a
  // per-monitor BarWidget (async, arrives whenever that widget's own
  // Component.onCompleted / property injection runs). Whichever finishes
  // second is the one that actually kicks off the first fetch.
  property bool settingsReady: false

  readonly property string pluginDir: {
    var url = Qt.resolvedUrl("Service.qml").toString()
    if (url.indexOf("file://") === 0) {
      var path = Model.filePathFromUrl(url)
      if (path) return path.substring(0, path.lastIndexOf("/"))
    }
    return ""
  }
  readonly property string binPath: root.pluginDir ? (root.pluginDir + "/bin/oma-channel") : ""

  function binCommand(args) {
    var cmd = [root.binPath || "oma-channel"]
    for (var i = 0; i < args.length; i++) cmd.push(String(args[i]))
    return cmd
  }

  // ---- settings, derived -----------------------------------------------
  property var subscriptions: []
  readonly property var configuredSubscriptions: root.subscriptions
  readonly property var configuredFeedUrls: {
    var urls = []
    for (var i = 0; i < root.subscriptions.length; i++) {
      if (root.subscriptions[i].enabled !== false) urls.push(root.subscriptions[i].url)
    }
    return urls
  }
  readonly property var configuredCategories: Model.extractCategories(root.subscriptions, root.items, root.readSet)
  readonly property var feedCategoryMap: {
    var map = {}
    for (var i = 0; i < root.subscriptions.length; i++) {
      map[root.subscriptions[i].url] = root.subscriptions[i].category || ""
    }
    return map
  }
  property int configuredMaxItemsPerFeed: 20
  property int configuredPollIntervalMinutes: 15
  property int configuredItemsPerPage: 10
  property int configuredRetentionDays: 30
  property bool configuredUnreadOnlyDefault: false
  property bool artworkEnabled: true
  property bool artworkAllowPageFetch: false
  // When on: publish a system-tray icon (StatusNotifierItem, via a
  // long-running `oma-channel tray` process) instead of always showing the
  // bar icon. See trayProcess below.
  property bool trayIconEnabled: false

  function configure(nextSettings) {
    var merged = nextSettings || {}
    var serialized = JSON.stringify(merged)
    if (serialized === root._lastSettingsJson) return
    root._lastSettingsJson = serialized
    root.settings = merged
    root.subscriptions = Model.normalizeSubscriptions(merged.subscriptions, merged.feedUrls)
    root.configuredMaxItemsPerFeed = Model.maxItemsPerFeed(merged.maxItemsPerFeed)
    root.configuredPollIntervalMinutes = Model.pollIntervalMinutes(merged.pollIntervalMinutes)
    root.configuredItemsPerPage = Model.pageSize(merged.itemsPerPage)
    root.configuredRetentionDays = Model.normalizeRetentionDays(merged.retentionDays)
    root.configuredUnreadOnlyDefault = merged.unreadOnlyDefault === true
    root.artworkEnabled = merged.artworkEnabled !== false
    root.artworkAllowPageFetch = merged.artworkAllowPageFetch === true
    root.trayIconEnabled = merged.trayIconEnabled === true
    var firstConfigure = !root.settingsReady
    root.settingsReady = true
    root.itemsUpdated()
    // The cache load may have already finished before settings first arrived
    // (listProcess.onExited's own fetchFeed() call would have no-op'd with
    // stateReady true but settingsReady still false); catch up here, once.
    if (firstConfigure && root.stateReady) root.fetchFeed()
  }

  function persistSettings(values) {
    var entry = { id: root.moduleId }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root._lastSettingsJson = JSON.stringify(entry)
    root.settings = entry
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.moduleId, entry)
  }

  function updateSubscriptions(subs) {
    var normalized = Model.normalizeSubscriptions(subs)
    var feedList = []
    for (var i = 0; i < normalized.length; i++) {
      if (normalized[i].enabled !== false) feedList.push(normalized[i].url)
    }
    root.subscriptions = normalized
    persistSettings({
      subscriptions: Model.serializeSubscriptions(normalized),
      feedUrls: Model.serializeFeedUrls(feedList)
    })
    fetchFeed()
    root.itemsUpdated()
    return normalized.length
  }

  function saveConfig(subs, minutes, perFeed, perPage, defaultUnreadOnly, retention, artwork, artworkPageFetch, trayIcon) {
    var normalized = Model.normalizeSubscriptions(subs !== undefined ? subs : root.configuredSubscriptions)
    var feedList = []
    for (var i = 0; i < normalized.length; i++) {
      if (normalized[i].enabled !== false) feedList.push(normalized[i].url)
    }
    var retDays = Model.normalizeRetentionDays(retention !== undefined ? retention : root.configuredRetentionDays)
    root.subscriptions = normalized
    persistSettings({
      subscriptions: Model.serializeSubscriptions(normalized),
      feedUrls: Model.serializeFeedUrls(feedList),
      pollIntervalMinutes: Model.pollIntervalMinutes(minutes),
      maxItemsPerFeed: Model.maxItemsPerFeed(perFeed),
      itemsPerPage: Model.pageSize(perPage),
      unreadOnlyDefault: defaultUnreadOnly === true,
      retentionDays: retDays,
      artworkEnabled: artwork !== false,
      artworkAllowPageFetch: artworkPageFetch === true,
      trayIconEnabled: trayIcon === true
    })
    fetchFeed()
  }

  // ---- article cache ------------------------------------------------------
  property var items: []
  readonly property var readSet: Model.collectReadIds(root.items)
  readonly property int badgeCount: Model.unreadCount(root.items, root.readSet)

  property bool isFetching: false
  property int totalFeeds: 0
  property int completedFeeds: 0
  property int failedFeeds: 0
  property bool refreshPending: false
  property bool stateReady: false

  property var lastImportResult: null
  property string lastImportMessage: ""
  property string selectedOpmlPath: ""
  property string selectedExportPath: ""

  // Fired after any state change a per-monitor BarWidget/Panel should
  // re-pull. Push-based rather than live bindings, matching how Panel.qml's
  // properties are plain settable fields rather than bindings to hostWidget.
  signal itemsUpdated()

  function applyRustPayload(rawJson) {
    var data
    try { data = JSON.parse(rawJson) } catch (e) { return }
    if (!data || typeof data !== "object") return
    root.items = Model.adaptRustItems(data.items)
    if (data.stats) {
      root.totalFeeds = data.stats.totalFeeds || 0
      root.completedFeeds = (data.stats.fetched || 0) + (data.stats.failed || 0)
      root.failedFeeds = data.stats.failed || 0
    }
    root.itemsUpdated()
  }

  function clearImportMessage() {
    root.lastImportMessage = ""
    root.lastImportResult = null
    root.itemsUpdated()
  }

  function setImportStatus(result, message) {
    root.lastImportResult = result
    root.lastImportMessage = message
    root.itemsUpdated()
  }

  function itemById(id) {
    for (var i = 0; i < root.items.length; i++) if (root.items[i].id === id) return root.items[i]
    return null
  }

  // ---- read state -----------------------------------------------------
  function markItemRead(item) { markItems([item], true) }
  function markItemUnread(item) { markItems([item], false) }

  function toggleItemRead(item) {
    var id = Model.itemIdentity(item)
    var it = root.itemById(id)
    markItems([item], !(it && it.read === true))
  }

  function markAllRead() {
    var ids = []
    for (var i = 0; i < root.items.length; i++) {
      if (root.items[i] && root.items[i].read !== true) ids.push(root.items[i].id)
    }
    if (!ids.length) return
    markItemsByIds(ids, true)
  }

  function markItems(itemList, read) {
    var ids = []
    for (var i = 0; i < (itemList || []).length; i++) {
      var id = Model.itemIdentity(itemList[i])
      if (id) ids.push(id)
    }
    markItemsByIds(ids, read)
  }

  function markItemsByIds(ids, read) {
    if (!ids || !ids.length) return
    root.items = Model.setItemsRead(root.items, ids, read === true)
    root.itemsUpdated()
    var payload = JSON.stringify({ ids: ids, read: read === true })
    markProcess.command = root.binCommand(["mark", "--input", payload])
    markProcess.running = true
  }

  // ReaderView hands back a full desired readSet; diff it against item flags.
  function applyLocalRead(next) {
    var target = {}
    for (var i = 0; i < (next || []).length; i++) {
      if (next[i]) target[next[i]] = true
    }
    var toRead = []
    var toUnread = []
    for (var j = 0; j < root.items.length; j++) {
      var it = root.items[j]
      if (!it || !it.id) continue
      var want = target[it.id] === true
      if (want !== (it.read === true)) {
        if (want) toRead.push(it.id)
        else toUnread.push(it.id)
      }
    }
    if (toRead.length) markItemsByIds(toRead, true)
    if (toUnread.length) markItemsByIds(toUnread, false)
  }

  // ---- bookmarks ------------------------------------------------------
  // Permanent by design: bookmarked articles survive unsubscribing their
  // feed, the per-feed item cap, and retention pruning -- see
  // state::merge_fetch and State::prune_retention on the Rust side.
  function toggleItemBookmark(item) {
    var id = Model.itemIdentity(item)
    var it = root.itemById(id)
    bookmarkItemsByIds([id], !(it && it.bookmarked === true))
  }

  function bookmarkItemsByIds(ids, bookmarked) {
    if (!ids || !ids.length) return
    root.items = Model.setItemsBookmarked(root.items, ids, bookmarked === true)
    root.itemsUpdated()
    var payload = JSON.stringify({ ids: ids, bookmarked: bookmarked === true })
    bookmarkProcess.command = root.binCommand(["bookmark", "--input", payload])
    bookmarkProcess.running = true
  }

  // ---- browser / clipboard actions -------------------------------------
  function openUrl(url) {
    if (!Model.isHttpsUrl(url)) return false
    Qt.openUrlExternally(url)
    return true
  }

  function activateItem(item) {
    var url = Model.activateUrl(item)
    if (!url) return
    Qt.openUrlExternally(url)
    markItems([item], true)
  }

  // ---- fetching ---------------------------------------------------------
  function fetchFeed() {
    if (!root.stateReady || !root.settingsReady) return
    if (fetchProcess.running) {
      root.refreshPending = true
      return
    }
    var enabledSubs = root.configuredSubscriptions.filter(function(s) { return s.enabled !== false })
    if (!enabledSubs.length) {
      root.isFetching = false
      root.refreshPending = false
      root.itemsUpdated()
      return
    }
    root.isFetching = true
    root.totalFeeds = enabledSubs.length
    root.completedFeeds = 0
    root.failedFeeds = 0
    root.itemsUpdated()
    var payload = JSON.stringify({ subscriptions: enabledSubs })
    fetchProcess.command = root.binCommand([
      "fetch",
      "--max-per-feed", root.configuredMaxItemsPerFeed,
      "--retention-days", root.configuredRetentionDays,
      "--input", payload
    ])
    fetchProcess.running = true
  }

  // ---- OPML import/export -----------------------------------------------
  function requestOpmlFileImport() {
    if (opmlSelectProcess.running || importOpmlProcess.running) return
    root.selectedOpmlPath = ""
    opmlSelectProcess.running = true
  }

  function handleSelectedOpmlFile(path) {
    if (!path) return
    importOpmlProcess.sourcePath = path
    importOpmlProcess.command = root.binCommand(["import-opml", path])
    importOpmlProcess.running = true
  }

  function defaultExportFilename() {
    var now = new Date()
    var year = now.getFullYear()
    var m = now.getMonth() + 1
    var d = now.getDate()
    var monthStr = m < 10 ? ("0" + m) : String(m)
    var dayStr = d < 10 ? ("0" + d) : String(d)
    return "oma-channel-" + year + "-" + monthStr + "-" + dayStr + ".opml"
  }

  function requestOpmlFileExport() {
    if (exportSelectProcess.running || exportOpmlProcess.running) return
    root.selectedExportPath = ""
    exportSelectProcess.defaultName = defaultExportFilename()
    exportSelectProcess.running = true
  }

  function handleSelectedExportFile(path) {
    if (!path) return
    if (!/\.opml$/i.test(path) && !/\.xml$/i.test(path)) path += ".opml"
    exportOpmlProcess.targetPath = path
    var payload = JSON.stringify({ subscriptions: root.configuredSubscriptions })
    exportOpmlProcess.command = root.binCommand(["export-opml", path, "--input", payload])
    exportOpmlProcess.running = true
  }

  // ---- artwork enrichment -------------------------------------------------
  // Deliberately its own subcommand rather than folded into fetch: image
  // downloads have a different latency/failure profile than feed fetches, so
  // this runs lazily on a short delay after a fetch completes and re-arms
  // itself while there is a backlog, never blocking fetchFeed().
  function scheduleEnrichArtwork() {
    if (!root.artworkEnabled) return
    enrichDelayTimer.restart()
  }

  function runEnrichArtwork() {
    if (!root.artworkEnabled || enrichArtworkProcess.running) return
    var args = ["enrich-artwork", "--budget", "6", "--network"]
    if (root.artworkAllowPageFetch) args.push("--allow-page-fetch")
    enrichArtworkProcess.command = root.binCommand(args)
    enrichArtworkProcess.running = true
  }

  Timer {
    id: enrichDelayTimer
    interval: 2000
    repeat: false
    onTriggered: root.runEnrichArtwork()
  }

  // ---- system tray icon ---------------------------------------------------
  // A long-running `oma-channel tray` process publishes a StatusNotifierItem
  // over D-Bus (see src/tray.rs) so the plugin can live in the system tray's
  // hover drawer instead of the bar strip. Explicit start/stop rather than a
  // plain `running: root.trayIconEnabled` binding, because the process can
  // die on its own (e.g. no StatusNotifierWatcher running yet) and needs a
  // bounded retry with backoff, not silent stay-dead.
  property int _trayRestartAttempts: 0
  readonly property int _trayMaxRestarts: 3

  function startTrayProcess() {
    if (!root.trayIconEnabled || trayProcess.running) return
    trayProcess.command = root.binCommand(["tray"])
    trayProcess.running = true
  }

  onTrayIconEnabledChanged: {
    if (root.trayIconEnabled) {
      root._trayRestartAttempts = 0
      root.startTrayProcess()
    } else {
      trayRestartTimer.stop()
      trayProcess.running = false
    }
  }

  Process {
    id: trayProcess
    running: false
    onExited: function(exitCode) {
      if (!root.trayIconEnabled) {
        root._trayRestartAttempts = 0
        return
      }
      if (root._trayRestartAttempts >= root._trayMaxRestarts) {
        console.warn("[OMA-CHANNEL] tray icon gave up after " + root._trayMaxRestarts
          + " attempts (exit " + exitCode + ") -- is a system tray (StatusNotifierWatcher) running?")
        return
      }
      root._trayRestartAttempts += 1
      trayRestartTimer.interval = Math.min(30000, 2000 * Math.pow(2, root._trayRestartAttempts))
      trayRestartTimer.start()
    }
  }

  Timer {
    id: trayRestartTimer
    repeat: false
    onTriggered: root.startTrayProcess()
  }

  // ---- cache maintenance IPC surface -------------------------------------
  function requestCleanup() {
    cleanupProcess.command = root.binCommand([
      "prune", "--retention-days", String(root.configuredRetentionDays)
    ])
    cleanupProcess.running = true
  }

  Process {
    id: cleanupProcess
    running: false
    onExited: root.fetchFeed()
  }

  Component.onCompleted: listProcess.running = true

  Timer {
    interval: root.configuredPollIntervalMinutes * 60 * 1000
    repeat: true
    running: root.configuredFeedUrls && root.configuredFeedUrls.length > 0
    onTriggered: root.fetchFeed()
  }

  // Native save-file dialog via the freedesktop portal (same approach as omarchy-file-select).
  readonly property string portalSaveScript: (
    "import argparse, os, sys, gi\n" +
    "gi.require_version('Gio', '2.0')\n" +
    "from gi.repository import Gio, GLib\n" +
    "parser = argparse.ArgumentParser(add_help=False)\n" +
    "parser.add_argument('--title', default='Save OPML file')\n" +
    "parser.add_argument('--default-name', default='__DEFAULT_NAME__')\n" +
    "parser.add_argument('--extensions', default='opml xml')\n" +
    "args, _ = parser.parse_known_args()\n" +
    "bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)\n" +
    "loop = GLib.MainLoop()\n" +
    "uris = []\n" +
    "def on_response(conn, sender, path, iface, sig, params):\n" +
    "    code, res = params.unpack()\n" +
    "    if code == 0:\n" +
    "        uris.extend(res.get('uris', []))\n" +
    "    loop.quit()\n" +
    "token = 'omarchysave%d' % os.getpid()\n" +
    "sender = bus.get_unique_name()[1:].replace('.', '_')\n" +
    "predicted = '/org/freedesktop/portal/desktop/request/%s/%s' % (sender, token)\n" +
    "bus.signal_subscribe('org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Request', 'Response', predicted, None, Gio.DBusSignalFlags.NONE, on_response)\n" +
    "exts = [e.lstrip('.').lower() for e in args.extensions.split()]\n" +
    "patterns = [(0, '*.' + e) for e in exts] + [(0, '*.' + e.upper()) for e in exts]\n" +
    "label = ' '.join('*.' + e for e in exts)\n" +
    "filters = GLib.Variant('a(sa(us))', [(label, patterns)])\n" +
    "options = {'handle_token': GLib.Variant('s', token), 'current_name': GLib.Variant('s', args.default_name), 'filters': filters, 'current_filter': GLib.Variant('(sa(us))', (label, patterns))}\n" +
    "try:\n" +
    "    handle = bus.call_sync('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop', 'org.freedesktop.portal.FileChooser', 'SaveFile', GLib.Variant('(ssa{sv})', ('', args.title, options)), None, Gio.DBusCallFlags.NONE, -1, None).unpack()[0]\n" +
    "    if handle != predicted:\n" +
    "        bus.signal_subscribe('org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Request', 'Response', handle, None, Gio.DBusSignalFlags.NONE, on_response)\n" +
    "except Exception as e:\n" +
    "    sys.exit(2)\n" +
    "GLib.timeout_add_seconds(600, loop.quit)\n" +
    "loop.run()\n" +
    "for u in uris:\n" +
    "    print(GLib.filename_from_uri(u)[0])\n" +
    "sys.exit(0 if uris else 1)\n"
  )

  Process {
    id: listProcess
    command: root.binCommand(["list"])
    stdout: StdioCollector {
      id: listStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.stateReady = true
      if (exitCode === 0 && listStdout.text) {
        root.applyRustPayload(listStdout.text)
      } else {
        console.warn("[OMA-CHANNEL] backend list failed — is the oma-channel binary installed? Run install.sh")
      }
      root.fetchFeed()
    }
  }

  Process {
    id: fetchProcess
    stdout: StdioCollector {
      id: fetchStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.isFetching = false
      if (exitCode === 0 && fetchStdout.text) {
        root.applyRustPayload(fetchStdout.text)
        root.scheduleEnrichArtwork()
      } else {
        root.failedFeeds = root.totalFeeds
        root.itemsUpdated()
      }
      if (root.refreshPending) {
        root.refreshPending = false
        root.fetchFeed()
      }
    }
  }

  Process {
    id: markProcess
    stdout: StdioCollector {
      id: markStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && markStdout.text) {
        root.applyRustPayload(markStdout.text)
      }
    }
  }

  Process {
    id: bookmarkProcess
    stdout: StdioCollector {
      id: bookmarkStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && bookmarkStdout.text) {
        root.applyRustPayload(bookmarkStdout.text)
      }
    }
  }

  Process {
    id: enrichArtworkProcess
    stdout: StdioCollector {
      id: enrichArtworkStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 || !enrichArtworkStdout.text) return
      var res
      try { res = JSON.parse(enrichArtworkStdout.text) } catch (e) { res = null }
      if (!res) return
      root.applyRustPayload(enrichArtworkStdout.text)
      // A full budget spent with something enriched means more is likely
      // still pending; drain the backlog with another pass after a gap.
      if (res.enriched > 0 && res.attempted >= 6) enrichDelayTimer.restart()
    }
  }

  Process {
    id: opmlSelectProcess
    command: ["omarchy-file-select", "--title", "Select OPML file", "--extensions", "opml xml"]
    stdout: StdioCollector {
      id: opmlSelectStdout
      waitForEnd: true
      onStreamFinished: {
        var path = String(opmlSelectStdout.text || "").trim()
        if (path) root.selectedOpmlPath = path
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && root.selectedOpmlPath) {
        root.handleSelectedOpmlFile(root.selectedOpmlPath)
      } else if (exitCode !== 0) {
        root.setImportStatus({ status: "error", imported: 0, duplicates: 0, invalid: 0, message: "No file selected" }, "")
      }
    }
  }

  Process {
    id: importOpmlProcess
    property string sourcePath: ""
    stdout: StdioCollector {
      id: importOpmlStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: importOpmlStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var err = String(importOpmlStderr.text || "").trim() || "Failed to parse OPML file"
        root.setImportStatus({ status: "error", imported: 0, duplicates: 0, invalid: 0, message: err }, err)
        return
      }
      var parsed
      try { parsed = JSON.parse(importOpmlStdout.text) } catch (e) { parsed = null }
      if (!parsed || !parsed.feeds) {
        root.setImportStatus({ status: "error", imported: 0, duplicates: 0, invalid: 0, message: "Invalid OPML content" }, "Invalid OPML content")
        return
      }
      var filename = Model.filenameFromPath(importOpmlProcess.sourcePath)
      var parseDetails = { feeds: Model.normalizeSubscriptions(parsed.feeds), totalFound: parsed.totalFound || parsed.feeds.length, invalidCount: parsed.invalid || 0 }
      var result = Model.calculateImportResult(root.configuredSubscriptions, parseDetails, filename)
      root.setImportStatus(result, result.message)
      if (result.status === "success" && (result.imported > 0 || result.duplicates > 0)) {
        root.subscriptions = Model.normalizeSubscriptions(result.newSubscriptions)
        root.persistSettings({
          subscriptions: Model.serializeSubscriptions(result.newSubscriptions),
          feedUrls: Model.serializeFeedUrls(result.newFeeds)
        })
        root.fetchFeed()
      }
      root.itemsUpdated()
    }
  }

  Process {
    id: exportSelectProcess
    property string defaultName: "oma-channel.opml"
    command: {
      var script = root.portalSaveScript.replace("__DEFAULT_NAME__", exportSelectProcess.defaultName)
      return ["python3", "-c", script]
    }
    stdout: StdioCollector {
      id: exportSelectStdout
      waitForEnd: true
      onStreamFinished: {
        var path = String(exportSelectStdout.text || "").trim()
        if (path) root.selectedExportPath = path
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && root.selectedExportPath) {
        root.handleSelectedExportFile(root.selectedExportPath)
      } else if (exitCode !== 0) {
        root.setImportStatus({ status: "error", message: "Export cancelled" }, "")
      }
    }
  }

  Process {
    id: exportOpmlProcess
    property string targetPath: ""
    stdout: StdioCollector { id: exportWriteStdout; waitForEnd: true }
    stderr: StdioCollector {
      id: exportWriteStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var err = String(exportWriteStderr.text || "").trim() || "Failed to write file"
        var msg = "Export failed: " + err
        root.setImportStatus({ status: "error", message: msg }, msg)
      } else {
        var out = {}
        try { out = JSON.parse(exportWriteStdout.text) } catch (e) { out = {} }
        var count = out.exported !== undefined ? out.exported : root.configuredSubscriptions.length
        var okMsg = "Saved " + Model.filenameFromPath(exportOpmlProcess.targetPath) + " (" + count + " feeds)"
        root.setImportStatus({ status: "success", message: okMsg, exported: count }, okMsg)
      }
      root.itemsUpdated()
    }
  }

  // ---- IPC ----------------------------------------------------------------
  // Panel open/close/toggle already work for any bar-widget-kind plugin via
  // the shell's own generic routing (`omarchy-shell shell summon|hide|toggle
  // <pluginId>`, which picks the focused monitor's instance and calls its
  // open()/close()/opened contract -- already implemented on BarWidget.qml).
  // What's missing without a service is everything that isn't UI: refreshing,
  // bulk read state, and machine-readable status.
  IpcHandler {
    target: root.moduleId

    function refresh(): string { root.fetchFeed(); return "ok" }
    function markAllRead(): string { root.markAllRead(); return "ok" }
    function cleanup(): string { root.requestCleanup(); return "ok" }
    // Panel open/close/toggle already work generically via
    // `omarchy-shell shell summon|hide|toggle <pluginId>` (see the block
    // comment above); "bookmarks" needs its own route because that generic
    // path carries no payload to say "open pre-filtered to saved articles".
    function bookmarks(): string {
      var widgets = root.shell && root.shell.bar && typeof root.shell.bar.moduleWidgets === "function"
        ? root.shell.bar.moduleWidgets(root.moduleId) : []
      var opened = false
      for (var i = 0; i < widgets.length; i++) {
        if (widgets[i] && typeof widgets[i].openBookmarks === "function") {
          widgets[i].openBookmarks()
          opened = true
        }
      }
      return opened ? "ok" : "no live widget"
    }
    function status(): string {
      return JSON.stringify({
        subscriptions: root.subscriptions.length,
        articles: root.items.length,
        unread: root.badgeCount,
        bookmarks: (function() {
          var n = 0
          for (var i = 0; i < root.items.length; i++) if (root.items[i].bookmarked) n++
          return n
        })(),
        isFetching: root.isFetching
      })
    }
  }
}
