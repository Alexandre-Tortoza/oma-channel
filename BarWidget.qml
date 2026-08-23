import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.alexmrtr.oma-channel"

  // Every business rule (fetching, the article cache, settings persistence,
  // bookmarks, artwork enrichment, OPML, IPC) lives in the single shared
  // Service instance -- see Service.qml. A bar surface is built once per
  // monitor, so this widget is itself instantiated once per monitor; it is a
  // thin view over the service plus the per-monitor popup panel.
  readonly property var rssService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.moduleName) : null

  readonly property var legacySettings: {
    var fromLayout = Model.entryFromLayout(root.bar && root.bar.layoutConfig, [
      "io.github.alexmrtr.oma-channel",
      "io.github.alexmrtr.rss-omareader",
      "io.github.sanjyay.rss-reeder"
    ])
    return fromLayout || ({})
  }

  function getSetting(key, fallback) {
    var val = setting(key, undefined)
    if (val !== undefined && val !== null) return val
    if (root.legacySettings && root.legacySettings[key] !== undefined && root.legacySettings[key] !== null) {
      return root.legacySettings[key]
    }
    return fallback
  }

  // Merges the legacy-migration fallback over this widget's own shell.json
  // entry into one flat object, so Service.configure() can read settings
  // directly without needing bar.layoutConfig access of its own.
  readonly property var mergedSettingsForService: {
    var merged = {}
    var legacy = root.legacySettings
    for (var k in legacy) merged[k] = legacy[k]
    var own = root.settings
    for (var k2 in own) merged[k2] = own[k2]
    return merged
  }

  function pushSettingsToService() {
    if (root.rssService) root.rssService.configure(root.mergedSettingsForService)
  }

  onBarChanged: { pushSettingsToService(); injectPanel() }
  onSettingsChanged: { pushSettingsToService(); injectPanel() }
  onRssServiceChanged: { pushSettingsToService(); injectPanel() }

  readonly property string configuredBarSection: {
    var fromLayout = Model.sectionFromLayout(root.bar && root.bar.layoutConfig, root.moduleName)
    if (fromLayout) return fromLayout
    return Model.barSection(getSetting("barSection", "right"))
  }

  readonly property var items: rssService ? rssService.items : []
  readonly property var readSet: rssService ? rssService.readSet : []
  readonly property int badgeCount: rssService ? rssService.badgeCount : 0
  readonly property bool isFetching: rssService ? rssService.isFetching === true : false
  readonly property int totalFeeds: rssService ? rssService.totalFeeds : 0
  readonly property int completedFeeds: rssService ? rssService.completedFeeds : 0
  readonly property int failedFeeds: rssService ? rssService.failedFeeds : 0
  readonly property var configuredSubscriptions: rssService ? rssService.configuredSubscriptions : []
  readonly property var configuredFeedUrls: rssService ? rssService.configuredFeedUrls : []
  readonly property var configuredCategories: rssService ? rssService.configuredCategories : []
  readonly property var feedCategoryMap: rssService ? rssService.feedCategoryMap : ({})
  readonly property int configuredMaxItemsPerFeed: rssService ? rssService.configuredMaxItemsPerFeed : 20
  readonly property int configuredPollIntervalMinutes: rssService ? rssService.configuredPollIntervalMinutes : 15
  readonly property int configuredItemsPerPage: rssService ? rssService.configuredItemsPerPage : 10
  readonly property int configuredRetentionDays: rssService ? rssService.configuredRetentionDays : 30
  readonly property bool configuredUnreadOnlyDefault: rssService ? rssService.configuredUnreadOnlyDefault === true : false
  readonly property bool configuredArtworkEnabled: rssService ? rssService.artworkEnabled !== false : true
  readonly property bool configuredArtworkAllowPageFetch: rssService ? rssService.artworkAllowPageFetch === true : false
  readonly property bool configuredTrayIconEnabled: rssService ? rssService.trayIconEnabled === true : false

  function applyBarSection(section) {
    var next = Model.barSection(section)
    persistSettingsLocal({ barSection: next })
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("omarchy bar move " + root.moduleName + " --section " + next)
  }

  // barSection is placement, not shared reading state, so it is written
  // straight through this widget's own settings rather than routed through
  // the service (which owns the reading-related keys only).
  function persistSettingsLocal(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target || !rssService) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = buttonLoader.item
    if ("hostWidget" in target) target.hostWidget = root
    if ("emptyCopy" in target) target.emptyCopy = Model.emptyPanelCopy(root.configuredFeedUrls)
    if ("items" in target) target.items = rssService.items
    if ("subscriptions" in target) target.subscriptions = root.configuredSubscriptions
    if ("feedUrls" in target) target.feedUrls = root.configuredFeedUrls
    if ("categories" in target) target.categories = root.configuredCategories
    if ("feedCategoryMap" in target) target.feedCategoryMap = root.feedCategoryMap
    if ("pollIntervalMinutes" in target) target.pollIntervalMinutes = root.configuredPollIntervalMinutes
    if ("maxItemsPerFeed" in target) target.maxItemsPerFeed = root.configuredMaxItemsPerFeed
    if ("itemsPerPage" in target) target.itemsPerPage = root.configuredItemsPerPage
    if ("retentionDays" in target) target.retentionDays = root.configuredRetentionDays
    if ("unreadOnlyDefault" in target) target.unreadOnlyDefault = root.configuredUnreadOnlyDefault
    if ("artworkEnabled" in target) target.artworkEnabled = root.configuredArtworkEnabled
    if ("artworkAllowPageFetch" in target) target.artworkAllowPageFetch = root.configuredArtworkAllowPageFetch
    if ("barSection" in target) target.barSection = root.configuredBarSection
    if ("readSet" in target) target.readSet = rssService.readSet
    if ("isFetching" in target) target.isFetching = rssService.isFetching
    if ("totalFeeds" in target) target.totalFeeds = rssService.totalFeeds
    if ("completedFeeds" in target) target.completedFeeds = rssService.completedFeeds
    if ("failedFeeds" in target) target.failedFeeds = rssService.failedFeeds
    if ("lastImportResult" in target) target.lastImportResult = rssService.lastImportResult
    if ("shareStatus" in target) target.shareStatus = rssService.lastImportMessage || ""
  }

  function clearImportMessage() {
    if (rssService) rssService.clearImportMessage()
  }

  // ---- proxies to the shared service --------------------------------------
  function fetchFeed() { if (rssService) rssService.fetchFeed() }
  function markItemRead(item) { if (rssService) rssService.markItemRead(item) }
  function markItemUnread(item) { if (rssService) rssService.markItemUnread(item) }
  function toggleItemRead(item) { if (rssService) rssService.toggleItemRead(item) }
  function markAllRead() { if (rssService) rssService.markAllRead() }
  function markItems(itemList, read) { if (rssService) rssService.markItems(itemList, read) }
  function markItemsByIds(ids, read) { if (rssService) rssService.markItemsByIds(ids, read) }
  function applyLocalRead(next) { if (rssService) rssService.applyLocalRead(next) }
  function toggleItemBookmark(item) { if (rssService) rssService.toggleItemBookmark(item) }
  function bookmarkItemsByIds(ids, bookmarked) { if (rssService) rssService.bookmarkItemsByIds(ids, bookmarked) }
  function activateItem(item) {
    if (rssService) rssService.activateItem(item)
    if (panelLoader.item) panelLoader.item.close()
  }

  function updateSubscriptions(subs) { return rssService ? rssService.updateSubscriptions(subs) : 0 }

  function saveConfig(subs, minutes, perFeed, perPage, section, defaultUnreadOnly, retention, artwork, artworkPageFetch) {
    if (rssService) rssService.saveConfig(subs, minutes, perFeed, perPage, defaultUnreadOnly, retention, artwork, artworkPageFetch)
    applyBarSection(section)
  }

  function requestOpmlFileImport() { if (rssService) rssService.requestOpmlFileImport() }
  function requestOpmlFileExport() { if (rssService) rssService.requestOpmlFileExport() }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    root.clearImportMessage()
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  // Opens the panel pre-filtered to saved articles.
  function openBookmarks() {
    root.open()
    if (panelLoader.item && typeof panelLoader.item.openBookmarks === "function") {
      panelLoader.item.openBookmarks()
    }
  }

  function closeForPopoutSwitch() {
    root.clearImportMessage()
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: buttonLoader.item ? buttonLoader.item.implicitWidth : 0
  implicitHeight: buttonLoader.item ? buttonLoader.item.implicitHeight : 0

  Connections {
    target: root.rssService
    function onItemsUpdated() { root.injectPanel() }
  }

  Component.onCompleted: pushSettingsToService()

  // When the tray icon is enabled (Service.qml publishes a StatusNotifierItem
  // and reacts to clicks itself), the bar-side affordance shrinks to a
  // near-zero anchor: the ModuleSlot in the bar collapses widgets down to
  // their implicitWidth, so a tiny nonzero size both frees the bar space and
  // keeps Panel.qml's popup anchoring at a stable point (a fully invisible
  // `visible:false` widget degrades to an arbitrary position between
  // neighboring bar widgets instead).
  Loader {
    id: buttonLoader
    anchors.fill: parent
    sourceComponent: root.configuredTrayIconEnabled ? trayAnchorComponent : normalButtonComponent
  }

  Component {
    id: normalButtonComponent
    BarIconButton {
      bar: root.bar
      text: "󰑫"
      tooltipText: root.badgeCount > 0 ? ("Oma Channel · " + root.badgeCount + " unread") : "Oma Channel"
      onPressed: function(buttonCode) {
        if (buttonCode === Qt.LeftButton) root.togglePanel()
      }
    }
  }

  Component {
    id: trayAnchorComponent
    Item {
      implicitWidth: 2
      implicitHeight: 2
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
