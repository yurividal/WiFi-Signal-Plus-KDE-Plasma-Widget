import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    // cfg_ prefix makes Plasma auto-load/save to Plasmoid.configuration
    property alias cfg_iconSize: iconSizeSpinBox.value

    Kirigami.FormLayout {
        anchors.left:  parent.left
        anchors.right: parent.right

        RowLayout {
            Kirigami.FormData.label: i18n("Tray icon size:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: iconSizeSpinBox
                from:     8
                to:       48
                stepSize: 2
                // Show "px" suffix
                textFromValue: (val) => val + " px"
                valueFromText: (text) => parseInt(text)
            }

            QQC2.Label {
                text: i18n("(system tray standard: 22 px)")
                color: Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
            }
        }
    }
}
