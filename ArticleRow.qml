import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var item: ({})
  property bool isRead: false
  property bool isBookmarked: false
  property bool isSelected: false
  property string categoryName: ""
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family

  signal activated()
  signal toggleRead()
  signal toggleBookmark()

  height: Style.space(42)
  width: parent ? parent.width : 300

  readonly property color mutedColor: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.45)
  readonly property bool hovered: mouseArea.containsMouse

  Rectangle {
    anchors.fill: parent
    radius: Style.space(4)
    color: root.isSelected
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
      : (root.hovered ? Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.05) : "transparent")

    Behavior on color { ColorAnimation { duration: 80 } }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  // Unread dot indicator
  Item {
    id: unreadDot
    anchors.left: parent.left
    anchors.leftMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(8)
    height: parent.height

    Rectangle {
      anchors.centerIn: parent
      width: root.isRead ? Style.space(4) : Style.space(6)
      height: width
      radius: width / 2
      color: root.isRead ? "transparent" : Color.accent
      border.color: root.isRead ? Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.15) : "transparent"
      border.width: 1
    }
  }

  // Action buttons visible on hover or selection (anchored right)
  Row {
    id: actionRow
    visible: root.hovered || root.isSelected
    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    // Mark read/unread toggle
    Rectangle {
      width: Style.space(22)
      height: Style.space(22)
      radius: Style.space(4)
      color: markHover.containsMouse ? Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.1) : "transparent"

      Text {
        anchors.centerIn: parent
        text: root.isRead ? "󰄱" : "󰄬"
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        color: root.isRead ? root.mutedColor : Color.accent
      }

      MouseArea {
        id: markHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleRead()
      }
    }

    // Bookmark toggle
    Rectangle {
      width: Style.space(22)
      height: Style.space(22)
      radius: Style.space(4)
      color: bookmarkHover.containsMouse ? Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.1) : "transparent"

      Text {
        anchors.centerIn: parent
        text: root.isBookmarked ? "󰓹" : "󰓾"
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        color: root.isBookmarked ? Color.accent : root.mutedColor
      }

      MouseArea {
        id: bookmarkHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleBookmark()
      }
    }

    // Open in browser button
    Rectangle {
      width: Style.space(22)
      height: Style.space(22)
      radius: Style.space(4)
      color: linkHover.containsMouse ? Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.1) : "transparent"

      Text {
        anchors.centerIn: parent
        text: "󰌹"
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        color: root.mutedColor
      }

      MouseArea {
        id: linkHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
      }
    }
  }

  // Artwork thumbnail, when the article has one cached locally. Only ever
  // points at a local file:// path already downloaded and MIME-sniffed by
  // the Rust backend -- never a remote URL from the feed.
  Image {
    id: thumbnail
    anchors.left: unreadDot.right
    anchors.leftMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    width: visible ? Style.space(32) : 0
    height: Style.space(32)
    visible: Boolean(root.item.artworkPath)
    source: root.item.artworkPath ? ("file://" + root.item.artworkPath) : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    smooth: true
    sourceSize.width: Style.space(64)
    sourceSize.height: Style.space(64)
  }

  // Title and metadata column (stretches to fill available space)
  Column {
    id: textCol
    anchors.left: thumbnail.visible ? thumbnail.right : unreadDot.right
    anchors.leftMargin: Style.space(6)
    anchors.right: actionRow.visible ? actionRow.left : parent.right
    anchors.rightMargin: actionRow.visible ? Style.space(4) : Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Text {
      width: parent.width
      text: (root.isBookmarked ? "󰓹 " : "") + (root.item.title || "Untitled")
      elide: Text.ElideRight
      textFormat: Text.PlainText
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      font.bold: !root.isRead
      color: root.isRead ? root.mutedColor : root.contentForeground
    }

    Text {
      width: parent.width
      text: {
        var parts = []
        if (root.categoryName) parts.push(root.categoryName)
        if (root.item.feedName) parts.push(root.item.feedName)
        var rel = Model.relativeTime(root.item.pubDateMs)
        if (rel) parts.push(rel)
        return parts.join(" · ")
      }
      elide: Text.ElideRight
      textFormat: Text.PlainText
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      color: root.mutedColor
    }
  }
}
