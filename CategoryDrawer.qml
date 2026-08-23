import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var categories: []
  property string selectedCategory: "all"
  property bool isOpen: false
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family

  signal categorySelected(string categoryId)
  signal closeRequested()

  readonly property int targetWidth: Style.space(142)

  width: root.isOpen ? targetWidth : 0
  clip: true

  Behavior on width {
    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.02)
    border.color: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.08)
    border.width: 1
    radius: Style.space(4)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(6)
      spacing: Style.space(5)

      // Drawer Header
      Row {
        width: parent.width
        height: Style.space(22)
        spacing: Style.space(4)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "CATEGORIES"
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          color: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.45)
        }
      }

      // Category List
      ListView {
        id: catList
        width: parent.width
        height: parent.height - Style.space(28)
        model: root.categories || []
        spacing: Style.space(4)
        clip: true

        delegate: Rectangle {
          id: catRow
          width: catList.width
          height: Style.space(30)
          radius: Style.space(4)

          readonly property bool isCurrent: (modelData.id || "all").toLowerCase() === root.selectedCategory.toLowerCase()
          readonly property bool hovered: rowMouse.containsMouse

          color: isCurrent
            ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
            : (hovered ? Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.07) : Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.035))
          border.color: isCurrent
            ? Color.accent
            : (hovered ? Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.14) : Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.07))
          border.width: 1

          Behavior on color { ColorAnimation { duration: 80 } }
          Behavior on border.color { ColorAnimation { duration: 80 } }

          Item {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)

            Rectangle {
              id: countBadge
              visible: (modelData.unreadCount || 0) > 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: Style.space(16)
              width: Math.max(height, badgeText.implicitWidth + Style.space(6))
              radius: height / 2
              color: isCurrent ? Color.accent : Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.12)

              Text {
                id: badgeText
                anchors.centerIn: parent
                text: String(modelData.unreadCount || 0)
                textFormat: Text.PlainText
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                color: isCurrent ? Color.background : root.contentForeground
              }
            }

            Text {
              anchors.left: parent.left
              anchors.right: countBadge.visible ? countBadge.left : parent.right
              anchors.rightMargin: countBadge.visible ? Style.space(6) : 0
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name || "All"
              elide: Text.ElideRight
              textFormat: Text.PlainText
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: isCurrent
              color: isCurrent ? Color.accent : Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.85)
            }
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.categorySelected(modelData.id || "all")
            }
          }
        }
      }
    }
  }
}
