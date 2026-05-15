/**
 * FullRepresentation.qml — WiFi Signal Plus popup panel
 *
 * Layout mirrors the GNOME extension screenshot:
 *   ┌─────────────────────────────────────────┐
 *   │  SSID name                   [gen icon] │
 *   │  WiFi 5 (802.11ac)                      │
 *   │  5 GHz · Ch 44                          │
 *   ├─── Performance ─────────────────────────┤
 *   │  Speed         ↑300 ↓270 Mbit/s         │
 *   │  ████████░░░░░░░░░░░                    │
 *   │  Width         40 MHz                   │
 *   │  ████░░░░░░░░░░░░░░░                    │
 *   │  Modulation    MCS 7 · 2×2 MIMO · 0.8µs │
 *   ├─── Signal ──────────────────────────────┤
 *   │  [signal graph]                         │
 *   │  Signal        -49 dBm (Excellent)      │
 *   │  Security      Open                     │
 *   │  BSSID         04:F0:21:25:47:46        │
 *   ├─── Access Points ───────────────────────┤
 *   │  ...                                    │
 *   ├─── Nearby Networks ─────────────────────┤
 *   │  ...                                    │
 *   └─────────────────────────────────────────┘
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components 3.0 as PC3
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami as Kirigami

import "../js/wifiGeneration.js" as WG

PlasmaExtras.Representation {
    id: fullRep

    property var info: root.wifiInfo
    readonly property bool connected: info && info.connected

    implicitWidth:  Kirigami.Units.gridUnit * 26
    implicitHeight: Kirigami.Units.gridUnit * 30

    header: PlasmaExtras.PlasmoidHeading {
        visible: false
    }

    QQC2.ScrollView {
        id: scrollView
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            id: mainColumn
            width: scrollView.availableWidth
            spacing: 0

            // ── Connection Header ─────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing / 2

                    PC3.Label {
                        text: connected ? info.ssid : "Not connected"
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.3
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    PC3.Label {
                        visible: connected
                        text: connected ? WG.getGenerationDescription(info.generation) : ""
                        opacity: 0.7
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.9
                    }
                    PC3.Label {
                        visible: connected
                        text: connected ? root.formatBand(info) : ""
                        opacity: 0.6
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.85
                    }
                }

                Image {
                    visible: connected && root.genIconSource(info.generation) !== ""
                    source: connected ? root.genIconSource(info.generation) : ""
                    Layout.preferredWidth:  72
                    Layout.preferredHeight: 72
                    Layout.maximumWidth:    72
                    Layout.maximumHeight:   72
                    Layout.alignment:       Qt.AlignVCenter
                    sourceSize.width:  144
                    sourceSize.height: 144
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }

            // ── Performance ───────────────────────────────────────────────
            SectionHeader { label: "Performance" }

            // Speed row with bar
            BarRow {
                label: "Speed"
                value: connected ? root.formatBitrate(info) : "--"
                barPercent: connected ? root.getSpeedPercent(info) : 0
                barColor: connected
                    ? root.speedQualityColors[WG.getSpeedQuality(
                          Math.max(info.txBitrate || 0, info.rxBitrate || 0, info.bitrate || 0))]
                    : "#62a0ea"
            }

            // Channel Width row with bar
            BarRow {
                label: "Width"
                value: connected && info.channelWidth ? info.channelWidth + " MHz" : "--"
                barPercent: connected ? root.getWidthPercent(info.channelWidth) : 0
                barColor: "#62a0ea"
            }

            // Modulation row (no bar)
            InfoRow {
                label: "Modulation"
                value: connected ? root.formatModulation(info) : "--"
            }

            // ── Signal ────────────────────────────────────────────────────
            SectionHeader { label: "Signal" }

            // Signal graph
            Item {
                Layout.fillWidth: true
                Layout.leftMargin:  Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                height: 80

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(1, 1, 1, 0.05)
                    radius: 4
                }

                Canvas {
                    id: signalCanvas
                    anchors.fill: parent

                    property var history: root.signalHistory

                    onHistoryChanged: requestPaint()
                    Component.onCompleted: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        const w = width, h = height
                        ctx.clearRect(0, 0, w, h)

                        const hist = root.signalHistory
                        if (hist.length < 2) return

                        const MIN_DBM = root.minSignalDbm
                        const MAX_DBM = root.maxSignalDbm
                        const MAX_HIST = root.signalHistoryMax

                        function mapY(dbm) {
                            const norm = Math.max(0, Math.min(1,
                                (dbm - MIN_DBM) / (MAX_DBM - MIN_DBM)))
                            return h * (1 - norm)
                        }

                        const stepX = w / (MAX_HIST - 1)
                        const startX = w - (hist.length - 1) * stepX

                        const latest = hist[hist.length - 1]
                        const quality = WG.getSignalQuality(latest)
                        const color = root.signalQualityColors[quality] || "#33d17a"

                        // Parse hex color to rgba
                        function hexToRgb(hex) {
                            const r = parseInt(hex.slice(1,3),16)/255
                            const g = parseInt(hex.slice(3,5),16)/255
                            const b = parseInt(hex.slice(5,7),16)/255
                            return [r,g,b]
                        }
                        const [r,g,b] = hexToRgb(color)

                        // Filled area
                        ctx.beginPath()
                        ctx.moveTo(startX, h)
                        for (let i = 0; i < hist.length; i++) {
                            ctx.lineTo(startX + i * stepX, mapY(hist[i]))
                        }
                        ctx.lineTo(startX + (hist.length - 1) * stepX, h)
                        ctx.closePath()
                        ctx.fillStyle = "rgba(" + Math.round(r*255) + "," +
                            Math.round(g*255) + "," + Math.round(b*255) + ",0.2)"
                        ctx.fill()

                        // Line
                        ctx.beginPath()
                        ctx.moveTo(startX, mapY(hist[0]))
                        for (let i = 1; i < hist.length; i++) {
                            ctx.lineTo(startX + i * stepX, mapY(hist[i]))
                        }
                        ctx.strokeStyle = "rgba(" + Math.round(r*255) + "," +
                            Math.round(g*255) + "," + Math.round(b*255) + ",0.85)"
                        ctx.lineWidth = 1.5
                        ctx.stroke()
                    }
                }
            }

            InfoRow {
                label: "Signal"
                value: connected ? root.formatSignal(info.signalStrength) : "--"
                valueColor: connected
                    ? root.signalQualityColors[WG.getSignalQuality(info.signalStrength)]
                    : Kirigami.Theme.textColor
            }

            InfoRow {
                label: "Security"
                value: connected ? info.security : "--"
            }

            InfoRow {
                label: "BSSID"
                value: connected ? info.bssid.toUpperCase() : "--"
            }

            // ── Access Points (same SSID, multiple BSSIDs) ────────────────
            Loader {
                Layout.fillWidth: true
                visible: connected && root.accessPoints.length > 0
                active: visible

                sourceComponent: ColumnLayout {
                    spacing: 0

                    SectionHeader { label: "Access Points" }

                    Repeater {
                        model: root.accessPoints
                        delegate: ApRow {
                            required property var modelData
                            ap: modelData
                            isActive: connected &&
                                      modelData.bssid === info.bssid
                        }
                    }
                }
            }

            // ── Nearby Networks ───────────────────────────────────────────
            Loader {
                Layout.fillWidth: true
                visible: root.nearbyNetworks.length > 0
                active: visible

                sourceComponent: ColumnLayout {
                    spacing: 0

                    SectionHeader { label: "Nearby Networks" }

                    Repeater {
                        model: root.nearbyNetworks
                        delegate: NearbyCard {
                            required property var modelData
                            network: modelData
                        }
                    }
                }
            }

            Item { height: Kirigami.Units.largeSpacing }
        }
    }

    // ── Section header component ──────────────────────────────────────────
    component SectionHeader: PlasmaExtras.PlasmoidHeading {
        id: sectionHeaderRoot
        property string label: ""

        Layout.fillWidth: true
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: Kirigami.Units.smallSpacing

        contentItem: PC3.Label {
            leftPadding: Kirigami.Units.largeSpacing
            text: sectionHeaderRoot.label
            color: Kirigami.Theme.highlightColor
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.85
            font.bold: true
            verticalAlignment: Text.AlignVCenter
        }
    }

    // ── Plain info row ────────────────────────────────────────────────────
    component InfoRow: RowLayout {
        required property string label
        required property string value
        property color valueColor: Kirigami.Theme.textColor

        Layout.fillWidth: true
        Layout.leftMargin:  Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        height: Kirigami.Units.gridUnit * 1.6
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            text: label
            opacity: 0.7
        }
        Item { Layout.fillWidth: true }
        PC3.Label {
            text: value
            color: valueColor
            font.family: "monospace"
        }
    }

    // ── Info row with progress bar ────────────────────────────────────────
    component BarRow: ColumnLayout {
        required property string label
        required property string value
        required property real   barPercent
        property color barColor: "#62a0ea"

        Layout.fillWidth: true
        Layout.leftMargin:  Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                text: label
                opacity: 0.7
            }
            Item { Layout.fillWidth: true }
            PC3.Label {
                text: value
                font.family: "monospace"
            }
        }

        // Bar track
        Item {
            Layout.fillWidth: true
            height: 3

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(1, 1, 1, 0.12)
                radius: 2
            }
            Rectangle {
                width: Math.max(0, Math.min(parent.width,
                    parent.width * barPercent / 100))
                height: parent.height
                color: barColor
                radius: 2
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }

        Item { height: Kirigami.Units.smallSpacing / 2 }
    }

    // ── Access Point row ──────────────────────────────────────────────────
    component ApRow: ColumnLayout {
        required property var  ap
        required property bool isActive

        Layout.fillWidth: true
        Layout.leftMargin:  Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // active indicator
            Kirigami.Icon {
                visible: isActive
                source: "emblem-ok-symbolic"
                width:  Kirigami.Units.iconSizes.small * 0.75
                height: width
            }
            Item {
                visible: !isActive
                width:  Kirigami.Units.iconSizes.small * 0.75
                height: width
            }

            // gen icon
            Image {
                visible: WG.getGenerationIconFilename(ap.generation) !== null
                source: root.genIconSource(ap.generation)
                Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                Layout.maximumWidth:    Kirigami.Units.iconSizes.small
                Layout.maximumHeight:   Kirigami.Units.iconSizes.small
                sourceSize.width:  Kirigami.Units.iconSizes.small * 2
                sourceSize.height: Kirigami.Units.iconSizes.small * 2
                fillMode: Image.PreserveAspectFit
            }

            PC3.Label {
                text: ap.bssid.toUpperCase()
                font.family: "monospace"
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            PC3.Label {
                text: ap.band + " · Ch " + ap.channel +
                      (ap.bandwidth > 20 ? " · " + ap.bandwidth + " MHz" : "")
                Layout.fillWidth: true
                opacity: 0.6
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                elide: Text.ElideRight
            }

            PC3.Label {
                visible: ap.maxBitrate > 0
                text: ap.maxBitrate + " Mbit/s"
                color: root.speedQualityColors[WG.getSpeedQuality(ap.maxBitrate)]
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            PC3.Label {
                text: ap.signalPercent + "%"
                color: root.signalQualityColors[
                           WG.getSignalQualityFromPercent(ap.signalPercent)] || "#ffffff"
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
        }

        // Signal bar
        Item {
            Layout.fillWidth: true
            height: 2

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(1, 1, 1, 0.1)
                radius: 1
            }
            Rectangle {
                readonly property string qual:
                    WG.getSignalQualityFromPercent(ap.signalPercent)
                width: Math.max(0, parent.width * ap.signalPercent / 100)
                height: parent.height
                color: root.signalQualityColors[qual] || "#ffffff"
                radius: 1
            }
        }

        Item { height: Kirigami.Units.smallSpacing }
    }

    // ── Nearby network card ───────────────────────────────────────────────
    component NearbyCard: ColumnLayout {
        id: nearbyCard
        required property var network

        Layout.fillWidth: true
        Layout.leftMargin:  Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: 2

        property bool expanded: false

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // gen icon
            Image {
                visible: WG.getGenerationIconFilename(network.bestAp.generation) !== null
                source: root.genIconSource(network.bestAp.generation)
                Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                Layout.maximumWidth:    Kirigami.Units.iconSizes.small
                Layout.maximumHeight:   Kirigami.Units.iconSizes.small
                sourceSize.width:  Kirigami.Units.iconSizes.small * 2
                sourceSize.height: Kirigami.Units.iconSizes.small * 2
                fillMode: Image.PreserveAspectFit
            }

            PC3.Label {
                text: network.ssid
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // security badge
            Rectangle {
                color: Qt.rgba(1, 1, 1, 0.1)
                radius: 3
                implicitWidth:  secLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                implicitHeight: secLabel.implicitHeight + 2

                PC3.Label {
                    id: secLabel
                    anchors.centerIn: parent
                    text: network.bestAp.security
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }

            // Expand toggle (always visible)
            PC3.ToolButton {
                icon.name: nearbyCard.expanded ? "go-up" : "go-down"
                implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
                implicitHeight: implicitWidth
                onClicked: nearbyCard.expanded = !nearbyCard.expanded
            }
        }

        // Signal bar (hidden when expanded)
        Item {
            visible: !nearbyCard.expanded
            Layout.fillWidth: true
            height: 2

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(1, 1, 1, 0.1)
                radius: 1
            }
            Rectangle {
                readonly property string qual:
                    WG.getSignalQualityFromPercent(network.bestAp.signalPercent)
                width: Math.max(0, parent.width * network.bestAp.signalPercent / 100)
                height: parent.height
                color: root.signalQualityColors[qual] || "#ffffff"
                radius: 1
            }
        }

        // Expanded AP list
        ColumnLayout {
            visible: nearbyCard.expanded
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: network.aps
                delegate: ApRow {
                    required property var modelData
                    ap: modelData
                    isActive: false
                }
            }
        }

        Item { height: Kirigami.Units.smallSpacing }
    }
}
