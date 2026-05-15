/**
 * WiFi Signal Plus — KDE Plasma 6 plasmoid
 *
 * Data sources (same as the GNOME extension):
 *  1. NetworkManager via org.kde.plasma.networkmanagement (NetworkModel).
 *     The Instantiator maps model roles to lowercase QML properties so they
 *     can be observed reactively.
 *  2. `iw dev <iface> link`  — generation, MCS, NSS, GI, channel-width, BSSID,
 *                              frequency, signal dBm, tx/rx bitrate
 *  3. `iw dev <iface> scan dump` — generation detection for nearby APs
 *
 *  iw parsing is a direct JS port of wifiGeneration.ts from the GNOME ext.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.components 3.0 as PC3
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.kirigami as Kirigami

import "../js/wifiGeneration.js" as WG

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation
    switchWidth:  Kirigami.Units.gridUnit * 24
    switchHeight: Kirigami.Units.gridUnit * 24

    // ── WiFi state ────────────────────────────────────────────────────────
    property var wifiInfo:        ({ connected: false })
    property var iwLinkInfo:      null
    property var scanGenerations: ({})
    property var accessPoints:    []
    property var nearbyNetworks:  []
    property var signalHistory:   []
    property string interfaceName: ""

    // Path to the Python NM D-Bus AP scanner script
    readonly property string nmApsScript:
        Qt.resolvedUrl("../scripts/nm_aps.py").toString().replace(/^file:\/\//, "")

    readonly property int signalHistoryMax: 60
    readonly property int maxSpeedMbps:     5760
    readonly property int maxWidthMhz:      320
    readonly property int minSignalDbm:     -90
    readonly property int maxSignalDbm:     -30

    readonly property var signalQualityColors: ({
        "Excellent": "#33d17a",
        "Good":      "#8ff0a4",
        "Fair":      "#f6d32d",
        "Weak":      "#ff7800",
        "Poor":      "#e01b24"
    })
    readonly property var speedQualityColors: ({
        "Excellent": "#c061cb",
        "VeryGood":  "#62a0ea",
        "Good":      "#33d17a",
        "OK":        "#f6d32d",
        "Weak":      "#ff7800",
        "Poor":      "#e01b24"
    })

    // ── NetworkModel — Qt binding to the NM daemon ────────────────────────
    PlasmaNM.NetworkModel { id: nmModel }

    PlasmaNM.AppletProxyModel {
        id: nmProxy
        sourceModel: nmModel
    }

    // ── Reactive NM watchers ──────────────────────────────────────────────
    // Instantiator delegates observe model role changes.
    // QML property names must start lowercase, so we map from model roles
    // (ConnectionState, Ssid, …) to camelCase lowercase names.
    Instantiator {
        id: nmInst
        model: nmProxy

        delegate: QtObject {
            // Bindings to model role names (via the implicit 'model' context).
            // These update reactively when the model emits dataChanged.
            property int    connectionState: model.ConnectionState  || 0
            property int    connType:        model.Type             || 0
            property string ssid:            model.Ssid             || ""
            property int    signalPct:       model.Signal           || 0
            property int    secType:         model.SecurityType     || 0
            property string deviceName:      model.DeviceName       || ""
            property string specificPath:    model.SpecificPath     || ""

            onConnectionStateChanged: Qt.callLater(root.syncFromNm)
            onDeviceNameChanged:      Qt.callLater(root.syncFromNm)
            onSsidChanged:            Qt.callLater(root.syncFromNm)
            onSignalPctChanged:       Qt.callLater(root.syncFromNm)
            onSecTypeChanged:         Qt.callLater(root.syncFromNm)
        }

        onCountChanged:  Qt.callLater(root.syncFromNm)
        onObjectAdded:   Qt.callLater(root.syncFromNm)
        onObjectRemoved: Qt.callLater(root.syncFromNm)
    }

    // ── Executable DataSource — runs `iw` commands ────────────────────────
    P5Support.DataSource {
        id: execSource
        engine: "executable"
        onNewData: (sourceName, data) => {
            const stdout  = data["stdout"] || ""
            const success = (data["exit code"] === 0)
            root.handleExecResult(sourceName, stdout, success)
            execSource.disconnectSource(sourceName)
        }
    }

    function runCmd(cmd) { execSource.connectSource(cmd) }

    Timer { id: refreshTimer; interval: 5000; running: true; repeat: true; onTriggered: root.syncFromNm() }
    Timer {
        id: bgScanTimer; interval: 60000; running: true; repeat: true
        onTriggered: {
            if (root.interfaceName) runCmd("iw dev " + root.interfaceName + " scan dump")
            runCmd("python3 " + root.nmApsScript)
        }
    }

    // Refresh AP data when the popup is opened
    onExpandedChanged: {
        if (root.expanded) {
            refreshTimer.restart()
            bgScanTimer.stop()
            root.syncFromNm()
            if (root.interfaceName) {
                runCmd("python3 " + root.nmApsScript)
                runCmd("iw dev " + root.interfaceName + " scan dump")
            }
        } else {
            bgScanTimer.restart()
        }
    }

    // ── Sync WiFi state from NM model ─────────────────────────────────────
    function syncFromNm() {
        let active     = null
        const wifiObjs = []

        for (let i = 0; i < nmInst.count; i++) {
            const obj = nmInst.objectAt(i)
            if (!obj) continue
            if (obj.connType !== PlasmaNM.Enums.Wireless) continue
            wifiObjs.push(obj)
            if (obj.connectionState === PlasmaNM.Enums.Activated) active = obj
        }

        if (!active) {
            root.wifiInfo       = { connected: false }
            root.interfaceName  = ""
            root.signalHistory  = []
            root.accessPoints   = []
            root.nearbyNetworks = []
            return
        }

        const devName = active.deviceName   || ""
        const ssid    = active.ssid         || ""
        const sigPct  = active.signalPct    || 0
        const secType = active.secType      || 0

        if (devName && devName !== root.interfaceName) {
            root.interfaceName = devName
            runCmd("iw dev " + devName + " scan dump")
        }
        if (devName) {
            runCmd("iw dev " + devName + " link")
            runCmd("python3 " + root.nmApsScript)
        }

        const iw   = root.iwLinkInfo
        const freq = iw ? (iw.frequency || 0) : 0

        root.wifiInfo = Object.freeze({
            connected:      true,
            interfaceName:  devName,
            ssid:           ssid,
            bssid:          iw ? (iw.bssid || "") : "",
            frequency:      freq,
            channel:        WG.frequencyToChannel(freq),
            band:           WG.frequencyToBand(freq),
            signalStrength: iw && iw.signal !== null ? iw.signal : WG.estimateSignalDbm(sigPct),
            signalPercent:  sigPct,
            bitrate:        iw ? Math.max(iw.txBitrate || 0, iw.rxBitrate || 0) : 0,
            security:       root.nmSecTypeToString(secType),
            generation:     iw ? iw.generation    : WG.WIFI_GENERATIONS.UNKNOWN,
            standard:       iw ? iw.standard      : null,
            mcs:            iw ? iw.mcs           : null,
            nss:            iw ? iw.nss           : null,
            guardInterval:  iw ? iw.guardInterval : null,
            channelWidth:   iw ? iw.channelWidth  : null,
            txBitrate:      iw ? iw.txBitrate     : null,
            rxBitrate:      iw ? iw.rxBitrate     : null,
            maxBitrate:     null,
        })

        if (iw && iw.signal !== null) root.pushSignalHistory(iw.signal)
        // AP / nearby network data populated by processNmAps() via handleExecResult.
    }

    function nmSecTypeToString(secType) {
        switch (secType) {
            case PlasmaNM.Enums.SAE:
            case PlasmaNM.Enums.Wpa3SuiteB192: return "WPA3"
            case PlasmaNM.Enums.Wpa2Eap:       return "WPA2-Enterprise"
            case PlasmaNM.Enums.Wpa2Psk:       return "WPA2"
            case PlasmaNM.Enums.WpaEap:        return "WPA-Enterprise"
            case PlasmaNM.Enums.WpaPsk:        return "WPA"
            case PlasmaNM.Enums.NoneSecurity:
            case PlasmaNM.Enums.OWE:           return "Open"
            default:                           return "Unknown"
        }
    }

    function handleExecResult(cmd, stdout, success) {
        if (cmd.includes("nm_aps.py")) {
            // NM access-point data from the Python D-Bus script
            if (success && stdout) {
                try {
                    const aps = JSON.parse(stdout)
                    if (Array.isArray(aps)) root.processNmAps(aps)
                } catch(e) {}
            }
        } else if (cmd.includes("scan")) {
            // iw scan dump → generation map
            if (success && stdout) {
                root.scanGenerations = WG.parseIwScanDump(stdout)
                root.refreshApGenerations()
            }
        } else {
            // iw link → detailed connection info
            if (success && stdout) {
                root.iwLinkInfo = WG.parseIwLinkOutput(stdout)
                const iw   = root.iwLinkInfo
                const base = root.wifiInfo
                if (base.connected) {
                    const freq = iw.frequency || base.frequency || 0
                    root.wifiInfo = Object.freeze(Object.assign({}, base, {
                        bssid:          iw.bssid         || base.bssid,
                        frequency:      freq,
                        channel:        WG.frequencyToChannel(freq),
                        band:           WG.frequencyToBand(freq),
                        signalStrength: iw.signal !== null ? iw.signal : base.signalStrength,
                        bitrate:        Math.max(iw.txBitrate || 0, iw.rxBitrate || 0, base.bitrate || 0),
                        generation:     iw.generation,
                        standard:       iw.standard,
                        mcs:            iw.mcs,
                        nss:            iw.nss,
                        guardInterval:  iw.guardInterval,
                        channelWidth:   iw.channelWidth || base.channelWidth,
                        txBitrate:      iw.txBitrate,
                        rxBitrate:      iw.rxBitrate,
                    }))
                    if (iw.signal !== null) root.pushSignalHistory(iw.signal)
                }
            }
        }
    }

    // Build accessPoints + nearbyNetworks from NM D-Bus AP data.
    // Called when nm_aps.py result arrives.
    function processNmAps(aps) {
        const activeSsid  = root.wifiInfo.connected ? (root.wifiInfo.ssid  || "") : ""
        const activeBssid = root.wifiInfo.connected ? (root.wifiInfo.bssid || "") : ""

        const newAccessPoints = []
        const grouped = {}

        for (const ap of aps) {
            const freq = ap.frequency || 0
            const gen  = root.scanGenerations[ap.bssid] || WG.WIFI_GENERATIONS.UNKNOWN
            const apObj = Object.freeze({
                bssid:         ap.bssid,
                ssid:          ap.ssid,
                frequency:     freq,
                channel:       WG.frequencyToChannel(freq),
                band:          WG.frequencyToBand(freq),
                bandwidth:     ap.bandwidth || 20,
                signalPercent: ap.strength  || 0,
                maxBitrate:    ap.maxBitrate || 0,
                security:      ap.security  || "Unknown",
                generation:    gen,
            })

            // Patch maxBitrate and bandwidth onto the active connection info
            if (ap.bssid === activeBssid && root.wifiInfo.connected) {
                const base = root.wifiInfo
                root.wifiInfo = Object.freeze(Object.assign({}, base, {
                    maxBitrate:  ap.maxBitrate || base.maxBitrate,
                    channelWidth: ap.bandwidth  || base.channelWidth,
                }))
            }

            if (ap.ssid === activeSsid) {
                newAccessPoints.push(apObj)
            } else {
                if (!grouped[ap.ssid]) grouped[ap.ssid] = []
                grouped[ap.ssid].push(apObj)
            }
        }

        root.accessPoints = newAccessPoints.sort((a, b) => b.signalPercent - a.signalPercent)

        const nearby = []
        for (const s in grouped) {
            const gpAps = grouped[s].sort((a, b) => b.signalPercent - a.signalPercent)
            nearby.push({ ssid: s, bestAp: gpAps[0], aps: gpAps })
        }
        root.nearbyNetworks = nearby.sort((a, b) => b.bestAp.signalPercent - a.bestAp.signalPercent)
    }

    // After a fresh iw scan dump, update the generation field on all cached APs.
    function refreshApGenerations() {
        if (root.accessPoints.length > 0) {
            root.accessPoints = root.accessPoints.map(ap => {
                const gen = root.scanGenerations[ap.bssid] || ap.generation
                return gen !== ap.generation ? Object.freeze(Object.assign({}, ap, { generation: gen })) : ap
            })
        }
        if (root.nearbyNetworks.length > 0) {
            root.nearbyNetworks = root.nearbyNetworks.map(net => {
                const aps = net.aps.map(ap => {
                    const gen = root.scanGenerations[ap.bssid] || ap.generation
                    return gen !== ap.generation ? Object.freeze(Object.assign({}, ap, { generation: gen })) : ap
                })
                return Object.assign({}, net, { aps: aps, bestAp: aps[0] })
            })
        }
    }

    function pushSignalHistory(dbm) {
        const hist = root.signalHistory.slice()
        hist.push(dbm)
        if (hist.length > root.signalHistoryMax) hist.shift()
        root.signalHistory = hist
    }

    function formatBitrate(info) {
        const tx = info.txBitrate, rx = info.rxBitrate
        let main
        if (tx != null && rx != null)
            main = (tx === rx) ? tx + " Mbit/s" : "↑" + tx + " ↓" + rx + " Mbit/s"
        else if (tx != null) main = "↑" + tx + " Mbit/s"
        else if (rx != null) main = "↓" + rx + " Mbit/s"
        else { const b = info.bitrate || 0; main = b > 0 ? b + " Mbit/s" : "--" }
        if (info.maxBitrate) main += " (max " + info.maxBitrate + ")"
        return main
    }

    function formatModulation(info) {
        const parts = []
        if (info.mcs !== null && info.mcs !== undefined) parts.push("MCS " + info.mcs)
        if (info.nss !== null && info.nss !== undefined) parts.push(info.nss + "×" + info.nss + " MIMO")
        if (info.guardInterval !== null && info.guardInterval !== undefined)
            parts.push("GI " + info.guardInterval + "µs")
        return parts.length > 0 ? parts.join(" · ") : "--"
    }

    function formatSignal(dbm) {
        if (dbm === null || dbm === undefined) return "--"
        return dbm + " dBm (" + WG.getSignalQuality(dbm) + ")"
    }

    function formatBand(info) {
        if (!info || !info.band) return "--"
        return info.band + (info.channel ? " · Ch " + info.channel : "")
    }

    function getSpeedPercent(info) {
        const speed = Math.max(info.txBitrate || 0, info.rxBitrate || 0, info.bitrate || 0)
        if (speed <= 0) return 0
        return Math.min(100, (Math.log(1 + speed) / Math.log(1 + root.maxSpeedMbps)) * 100)
    }

    function getWidthPercent(width) {
        if (!width) return 0
        return Math.min(100, (width / root.maxWidthMhz) * 100)
    }

    function genIconSource(generation) {
        const name = WG.getGenerationIconFilename(generation)
        return name ? Qt.resolvedUrl("../icons/" + name) : ""
    }

    // ── Compact representation ────────────────────────────────────────────
    compactRepresentation: Item {
        // Layout.preferredWidth is a size *hint* for the panel. The system tray
        // ignores it and manages icon sizes itself — so no maximumWidth here, or
        // the system tray gets an over-constrained slot and renders oddly.
        Layout.preferredWidth: Plasmoid.configuration.iconSize

        readonly property string genSrc: root.wifiInfo.connected
            ? root.genIconSource(root.wifiInfo.generation) : ""

        Kirigami.Icon {
            id: genIcon
            anchors.fill: parent
            visible: parent.genSrc !== ""
            source:  parent.genSrc
            // isMask:false keeps PNG colours untouched (no theme colourisation)
            isMask: false
        }

        PC3.Label {
            anchors.centerIn: parent
            visible: root.wifiInfo.connected && !genIcon.visible
            text: WG.getGenerationLabel(root.wifiInfo.connected ? root.wifiInfo.generation : 0)
            font.bold: true
            font.pixelSize: parent.height * 0.45
        }

        MouseArea {
            anchors.fill: parent
            // Capture expanded state at press time. Without this, if the popup
            // is already open the system tray closes it first, then our
            // onClicked evaluates !expanded = true and immediately reopens it,
            // making the click appear to do nothing.
            property bool wasExpanded: false
            onPressed:  wasExpanded = root.expanded
            onClicked:  root.expanded = !wasExpanded
        }
    }

    // ── Full representation ───────────────────────────────────────────────
    fullRepresentation: FullRepresentation { }
}
