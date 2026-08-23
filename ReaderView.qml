import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var hostWidget: null
  property var items: []
  property var subscriptions: []
  property var categories: []
  property var feedCategoryMap: ({})
  property var readSet: []
  property string emptyCopy: "Add feed URLs in Settings."
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family
  property int itemsPerPage: 10
  property bool unreadOnlyDefault: false
  property bool isFetching: hostWidget ? hostWidget.isFetching === true : false
  property int totalFeeds: hostWidget ? hostWidget.totalFeeds : 0
  property int completedFeeds: hostWidget ? hostWidget.completedFeeds : 0
  property int failedFeeds: hostWidget ? hostWidget.failedFeeds : 0

  property string currentCategory: "all"
  property bool unreadOnly: unreadOnlyDefault
  property bool bookmarkedOnly: false
  property string searchQuery: ""
  property int currentPage: 0
  property int selectedIndex: 0
  property bool drawerOpen: false

  signal openSettingsRequested()
  signal refreshRequested()
  signal markAllReadRequested()

  function toggleCategoryDrawer() {
    root.drawerOpen = !root.drawerOpen
  }

  function focusSearch() {
    searchField.focusField()
  }

  function selectNextArticle() {
    if (pageArticles.length === 0) return
    root.selectedIndex = Math.min(pageArticles.length - 1, root.selectedIndex + 1)
  }

  function selectPrevArticle() {
    if (pageArticles.length === 0) return
    root.selectedIndex = Math.max(0, root.selectedIndex - 1)
  }

  function activateCurrentArticle() {
    if (pageArticles.length === 0) return
    var item = pageArticles[root.selectedIndex]
    if (item) root.activateItem(item)
  }

  function toggleReadCurrentArticle() {
    if (pageArticles.length === 0) return
    var item = pageArticles[root.selectedIndex]
    if (item) root.toggleReadItem(item)
  }

  function toggleBookmarkCurrentArticle() {
    if (pageArticles.length === 0) return
    var item = pageArticles[root.selectedIndex]
    if (item) root.toggleBookmarkItem(item)
  }

  function toggleBookmarkItem(item) {
    if (!item) return
    if (root.hostWidget && typeof root.hostWidget.toggleItemBookmark === "function") {
      root.hostWidget.toggleItemBookmark(item)
    }
  }

  function activateItem(item) {
    if (root.hostWidget && typeof root.hostWidget.activateItem === "function") {
      root.hostWidget.activateItem(item)
    } else {
      var url = Model.activateUrl(item)
      if (url) Qt.openUrlExternally(url)
    }
  }

  function toggleReadItem(item) {
    if (!item) return
    var isCurrentlyRead = Model.isRead(root.readSet, item)
    if (isCurrentlyRead) {
      // Mark unread by removing from readSet
      var next = []
      var id = Model.itemIdentity(item)
      for (var i = 0; i < root.readSet.length; i++) {
        if (root.readSet[i] !== id) next.push(root.readSet[i])
      }
      if (root.hostWidget && typeof root.hostWidget.applyLocalRead === "function") {
        root.hostWidget.applyLocalRead(next)
      }
    } else {
      if (root.hostWidget && typeof root.hostWidget.markItemRead === "function") {
        root.hostWidget.markItemRead(item)
      }
    }
  }

  // Derived filtered articles model
  readonly property var allFilteredArticles: Model.filterReaderArticles(root.items, {
    category: root.currentCategory,
    unreadOnly: root.unreadOnly,
    bookmarkedOnly: root.bookmarkedOnly,
    search: root.searchQuery,
    readSet: root.readSet,
    subscriptions: root.subscriptions,
    feedCategoryMap: root.feedCategoryMap
  })

  readonly property int totalFilteredCount: allFilteredArticles.length
  readonly property int totalPages: Math.max(1, Math.ceil(totalFilteredCount / Math.max(1, root.itemsPerPage)))
  readonly property var pageArticles: {
    var start = root.currentPage * root.itemsPerPage
    return allFilteredArticles.slice(start, start + root.itemsPerPage)
  }

  readonly property int totalUnreadCount: Model.unreadCount(root.items, root.readSet)
  readonly property bool hasCategories: (root.categories || []).length > 1

  onCurrentCategoryChanged: {
    root.currentPage = 0
    root.selectedIndex = 0
  }

  onUnreadOnlyChanged: {
    root.currentPage = 0
    root.selectedIndex = 0
  }

  onBookmarkedOnlyChanged: {
    root.currentPage = 0
    root.selectedIndex = 0
  }

  onSearchQueryChanged: {
    root.currentPage = 0
    root.selectedIndex = 0
  }

  // 1. Header Bar (anchored top)
  Item {
    id: headerBar
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(30)

    // Status Metadata (left-aligned)
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: {
        var subCount = (root.subscriptions || []).length
        return subCount + (subCount === 1 ? " feed" : " feeds") + " · " + root.totalUnreadCount + " unread"
      }
      textFormat: Text.PlainText
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.55)
    }

    // Actions (Refresh & Settings) (right) - scaled ~15%
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      // Refresh action
      Rectangle {
        width: Style.space(30)
        height: Style.space(30)
        radius: Style.space(4)
        color: refreshHover.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : "transparent"

        Text {
          anchors.centerIn: parent
          text: "󰑐"
          font.family: root.contentFontFamily
          font.pixelSize: Math.round(Style.font.body * 1.15)
          color: root.isFetching ? Color.accent : root.contentForeground
          opacity: root.isFetching ? 0.75 : 1.0
        }

        MouseArea {
          id: refreshHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.refreshRequested()
        }
      }

      // Settings action
      Rectangle {
        width: Style.space(30)
        height: Style.space(30)
        radius: Style.space(4)
        color: settingsHover.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : "transparent"

        Text {
          anchors.centerIn: parent
          text: "󰒓"
          font.family: root.contentFontFamily
          font.pixelSize: Math.round(Style.font.body * 1.15)
          color: root.contentForeground
        }

        MouseArea {
          id: settingsHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openSettingsRequested()
        }
      }
    }
  }

  // 2. Responsive Toolbar (anchored below header)
  Item {
    id: toolbarBar
    anchors.top: headerBar.bottom
    anchors.topMargin: Style.space(6)
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(28)

    Row {
      id: toolbarLeft
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      // Category Drawer Toggle (only if categories exist)
      Rectangle {
        visible: root.hasCategories
        width: Style.space(26)
        height: Style.space(26)
        radius: Style.space(4)
        color: root.drawerOpen
          ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
          : (drawerHover.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : "transparent")
        border.color: root.drawerOpen ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "󰍜"
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          color: root.drawerOpen ? Color.accent : root.contentForeground
        }

        MouseArea {
          id: drawerHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleCategoryDrawer()
        }
      }

      // Scope Pill Badge
      Rectangle {
        id: scopeBtn
        height: Style.space(26)
        width: scopeText.implicitWidth + Style.space(16)
        radius: Style.space(4)
        readonly property bool isCustomCat: root.currentCategory.toLowerCase() !== "all"
        color: isCustomCat
          ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
          : (scopeHover.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04))
        border.color: isCustomCat
          ? Color.accent
          : (scopeHover.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1))
        border.width: 1

        Behavior on color { ColorAnimation { duration: 80 } }
        Behavior on border.color { ColorAnimation { duration: 80 } }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(4)

          Text {
            id: scopeText
            text: root.currentCategory.toLowerCase() === "all" ? "All feeds" : root.currentCategory
            textFormat: Text.PlainText
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            color: scopeBtn.isCustomCat ? Color.accent : root.contentForeground
          }
        }

        MouseArea {
          id: scopeHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.currentCategory.toLowerCase() !== "all") {
              root.currentCategory = "all"
            } else if (root.hasCategories) {
              root.toggleCategoryDrawer()
            }
          }
        }
      }

      // Unread-Only Toggle Chip
      Rectangle {
        id: unreadBtn
        height: Style.space(26)
        width: unreadText.implicitWidth + Style.space(18)
        radius: Style.space(4)
        color: root.unreadOnly
          ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
          : (unreadHover.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04))
        border.color: root.unreadOnly
          ? Color.accent
          : (unreadHover.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1))
        border.width: 1

        Behavior on color { ColorAnimation { duration: 80 } }
        Behavior on border.color { ColorAnimation { duration: 80 } }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(5)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(5)
            height: width
            radius: width / 2
            color: root.unreadOnly ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.4)
          }

          Text {
            id: unreadText
            text: "Unread"
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            color: root.unreadOnly ? Color.accent : root.contentForeground
          }
        }

        MouseArea {
          id: unreadHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.unreadOnly = !root.unreadOnly
        }
      }

      // Saved/bookmarked-Only Toggle Chip
      Rectangle {
        id: savedBtn
        height: Style.space(26)
        width: savedText.implicitWidth + Style.space(18)
        radius: Style.space(4)
        color: root.bookmarkedOnly
          ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
          : (savedHover.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04))
        border.color: root.bookmarkedOnly
          ? Color.accent
          : (savedHover.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1))
        border.width: 1

        Behavior on color { ColorAnimation { duration: 80 } }
        Behavior on border.color { ColorAnimation { duration: 80 } }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(5)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.bookmarkedOnly ? "󰓹" : "󰓾"
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            color: root.bookmarkedOnly ? Color.accent : root.contentForeground
          }

          Text {
            id: savedText
            text: "Saved"
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            color: root.bookmarkedOnly ? Color.accent : root.contentForeground
          }
        }

        MouseArea {
          id: savedHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.bookmarkedOnly = !root.bookmarkedOnly
        }
      }
    }

    // Search Field (reclaims remaining width up to parent.right)
    SearchField {
      id: searchField
      anchors.left: toolbarLeft.right
      anchors.leftMargin: Style.space(6)
      anchors.right: parent.right
      anchors.rightMargin: 0
      anchors.verticalCenter: parent.verticalCenter
      contentForeground: root.contentForeground
      contentFontFamily: root.contentFontFamily
      onTextChanged: root.searchQuery = text
      onCleared: root.searchQuery = ""
    }
  }

  // 3. Main Content Area (Drawer + Articles filling remaining height)
  Item {
    id: mainContentArea
    anchors.top: toolbarBar.bottom
    anchors.topMargin: Style.space(6)
    anchors.bottom: footerBar.top
    anchors.bottomMargin: Style.space(6)
    anchors.left: parent.left
    anchors.right: parent.right

    // Category Drawer
    CategoryDrawer {
      id: catDrawer
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      isOpen: root.drawerOpen && root.hasCategories
      categories: root.categories || []
      selectedCategory: root.currentCategory
      contentForeground: root.contentForeground
      contentFontFamily: root.contentFontFamily
      onCategorySelected: function(catId) {
        root.currentCategory = catId
      }
      onCloseRequested: root.drawerOpen = false
    }

    // Article List Container
    Item {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: (catDrawer.width > 0) ? catDrawer.right : parent.left
      anchors.leftMargin: (catDrawer.width > 0) ? Style.space(8) : 0
      anchors.right: parent.right

      // Empty state message
      Column {
        anchors.centerIn: parent
        spacing: Style.space(8)
        visible: root.pageArticles.length === 0

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: (root.subscriptions || []).length === 0 ? "󰑫" : (root.isFetching ? "󰑐" : "󰄬")
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.title
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.3)
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: {
            if ((root.subscriptions || []).length === 0) return root.emptyCopy
            if (root.isFetching && root.items.length === 0) {
              if (root.totalFeeds > 0) {
                return "Loading feeds… " + root.completedFeeds + " / " + root.totalFeeds
              }
              return "Loading feeds…"
            }
            if (root.searchQuery) return "No articles match \"" + root.searchQuery + "\""
            if (root.bookmarkedOnly) return "No saved articles yet"
            if (root.unreadOnly) return "All caught up! No unread articles"
            if (root.isFetching) {
              if (root.totalFeeds > 0) {
                return "Loading feeds… " + root.completedFeeds + " / " + root.totalFeeds
              }
              return "Loading feeds…"
            }
            return "No articles in this category"
          }
          textFormat: Text.PlainText
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.5)
        }
      }

      // Articles ListView (fills available container height)
      ListView {
        id: articleListView
        anchors.fill: parent
        visible: root.pageArticles.length > 0
        model: root.pageArticles
        spacing: Style.space(2)
        clip: true

        delegate: ArticleRow {
          item: modelData
          isRead: Model.isRead(root.readSet, modelData)
          isBookmarked: modelData.bookmarked === true
          isSelected: index === root.selectedIndex
          categoryName: modelData.category || root.feedCategoryMap[modelData.feedUrl] || ""
          contentForeground: root.contentForeground
          contentFontFamily: root.contentFontFamily

          onActivated: root.activateItem(modelData)
          onToggleRead: root.toggleReadItem(modelData)
          onToggleBookmark: root.toggleBookmarkItem(modelData)
        }
      }
    }
  }

  // 4. Footer Pagination & Status (anchored at bottom)
  Item {
    id: footerBar
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(22)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: paginationRow.visible ? paginationRow.left : parent.right
      anchors.rightMargin: Style.space(8)
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: {
        var start = root.currentPage * root.itemsPerPage + 1
        var end = Math.min(root.totalFilteredCount, (root.currentPage + 1) * root.itemsPerPage)
        if (root.isFetching && root.totalFeeds > 0) {
          if (root.totalFilteredCount === 0) {
            return "Loading feeds… " + root.completedFeeds + " / " + root.totalFeeds
          }
          return "Showing " + start + "-" + end + " of " + root.totalFilteredCount + " · Updating (" + root.completedFeeds + "/" + root.totalFeeds + ")"
        }
        if (root.totalFilteredCount === 0) return "0 articles"
        return "Showing " + start + "-" + end + " of " + root.totalFilteredCount
      }
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.4)
    }

    // Pagination controls (Prev / Page Indicator / Next)
    Row {
      id: paginationRow
      visible: root.totalPages > 1
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Rectangle {
        width: Style.space(22)
        height: Style.space(22)
        radius: Style.space(4)
        color: prevMouse.containsMouse && root.currentPage > 0 ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : "transparent"
        opacity: root.currentPage > 0 ? 1.0 : 0.3

        Text {
          anchors.centerIn: parent
          text: "󰅁"
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          color: root.contentForeground
        }

        MouseArea {
          id: prevMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.currentPage > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: {
            if (root.currentPage > 0) {
              root.currentPage--
              root.selectedIndex = 0
            }
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: (root.currentPage + 1) + " / " + root.totalPages
        textFormat: Text.PlainText
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.6)
      }

      Rectangle {
        width: Style.space(22)
        height: Style.space(22)
        radius: Style.space(4)
        color: nextMouse.containsMouse && root.currentPage < root.totalPages - 1 ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : "transparent"
        opacity: root.currentPage < root.totalPages - 1 ? 1.0 : 0.3

        Text {
          anchors.centerIn: parent
          text: "󰅂"
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          color: root.contentForeground
        }

        MouseArea {
          id: nextMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.currentPage < root.totalPages - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: {
            if (root.currentPage < root.totalPages - 1) {
              root.currentPage++
              root.selectedIndex = 0
            }
          }
        }
      }
    }
  }
}
