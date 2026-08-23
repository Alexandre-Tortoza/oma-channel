import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property alias text: input.text
  property string placeholderText: "Search articles... (/)"
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family

  signal cleared()

  function focusField() {
    input.forceActiveFocus()
  }

  function clearField() {
    input.text = ""
    root.cleared()
  }

  height: Style.space(28)
  implicitWidth: 160

  Rectangle {
    anchors.fill: parent
    radius: Style.space(4)
    color: input.activeFocus
      ? Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.08)
      : Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.04)
    border.color: input.activeFocus ? Color.accent : Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.1)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 80 } }
    Behavior on border.color { ColorAnimation { duration: 80 } }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰍉"
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.4)
      }

      TextInput {
        id: input
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(16) - (clearBtn.visible ? Style.space(16) : 0)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        color: root.contentForeground
        selectByMouse: true
        clip: true

        Text {
          anchors.fill: parent
          text: root.placeholderText
          textFormat: Text.PlainText
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.3)
          visible: !input.text && !input.activeFocus
          verticalAlignment: Text.AlignVCenter
        }
      }

      Text {
        id: clearBtn
        visible: Boolean(input.text)
        anchors.verticalCenter: parent.verticalCenter
        text: "󰅖"
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        color: clearMouse.containsMouse ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.4)

        MouseArea {
          id: clearMouse
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.clearField()
        }
      }
    }
  }
}
