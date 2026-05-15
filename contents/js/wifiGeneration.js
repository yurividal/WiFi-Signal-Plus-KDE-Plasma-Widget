"use strict";
/**
 * WiFi Generation Detection
 *
 * Direct port of wifiGeneration.ts from the GNOME extension.
 * Parses `iw dev <interface> link` and `iw dev <interface> scan dump`
 * output to detect WiFi 4/5/6/6E/7.
 */

const WIFI_GENERATIONS = {
    UNKNOWN: 0,
    WIFI_1: 1,
    WIFI_2: 2,
    WIFI_3: 3,
    WIFI_4: 4,
    WIFI_5: 5,
    WIFI_6: 6,
    WIFI_7: 7,
};

const IEEE_STANDARDS = {
    [WIFI_GENERATIONS.WIFI_1]: '802.11b',
    [WIFI_GENERATIONS.WIFI_2]: '802.11a',
    [WIFI_GENERATIONS.WIFI_3]: '802.11g',
    [WIFI_GENERATIONS.WIFI_4]: '802.11n',
    [WIFI_GENERATIONS.WIFI_5]: '802.11ac',
    [WIFI_GENERATIONS.WIFI_6]: '802.11ax',
    [WIFI_GENERATIONS.WIFI_7]: '802.11be',
    [WIFI_GENERATIONS.UNKNOWN]: 'Unknown',
};

const GUARD_INTERVALS = {
    SHORT: 0.4,
    NORMAL: 0.8,
    LONG_1: 1.6,
    LONG_2: 3.2,
};

const HE_GI_INDEX_MAP = {
    0: GUARD_INTERVALS.NORMAL,
    1: GUARD_INTERVALS.LONG_1,
    2: GUARD_INTERVALS.LONG_2,
};

const WIFI_1_MAX_BITRATE = 11;
const FREQ_5GHZ_START = 5000;

function isKnownGeneration(gen) {
    return gen >= WIFI_GENERATIONS.WIFI_1 && gen <= WIFI_GENERATIONS.WIFI_7;
}

function createEmptyIwLinkInfo() {
    return {
        generation: WIFI_GENERATIONS.UNKNOWN,
        standard: null,
        mcs: null,
        nss: null,
        guardInterval: null,
        channelWidth: null,
        txBitrate: null,
        rxBitrate: null,
        signal: null,
        frequency: null,
        ssid: null,
        bssid: null,
    };
}

function parseIwLinkOutput(iwOutput) {
    if (!iwOutput || iwOutput.includes('Not connected')) {
        return createEmptyIwLinkInfo();
    }

    const result = {
        generation: WIFI_GENERATIONS.UNKNOWN,
        standard: null,
        mcs: null,
        nss: null,
        guardInterval: null,
        channelWidth: null,
        txBitrate: null,
        rxBitrate: null,
        signal: null,
        frequency: null,
        ssid: null,
        bssid: null,
    };

    for (const line of iwOutput.split('\n')) {
        parseLine(line.trim(), result);
    }

    detectLegacyGeneration(result);

    if (isKnownGeneration(result.generation)) {
        result.standard = IEEE_STANDARDS[result.generation];
    }

    return Object.freeze(result);
}

function detectLegacyGeneration(result) {
    if (result.generation !== WIFI_GENERATIONS.UNKNOWN) return;
    if (result.frequency === null) return;

    if (result.frequency >= FREQ_5GHZ_START) {
        result.generation = WIFI_GENERATIONS.WIFI_2;
        return;
    }

    const maxBitrate = Math.max(result.txBitrate ?? 0, result.rxBitrate ?? 0);
    if (maxBitrate === 0) return;

    result.generation = maxBitrate <= WIFI_1_MAX_BITRATE
        ? WIFI_GENERATIONS.WIFI_1
        : WIFI_GENERATIONS.WIFI_3;
}

function parseLine(line, result) {
    parseConnectionInfo(line, result);
    parseBitrateLines(line, result);
}

function parseConnectionInfo(line, result) {
    if (line.startsWith('SSID:')) {
        result.ssid = line.substring(5).trim();
        return;
    }

    if (line.startsWith('Connected to')) {
        const match = line.match(/Connected to ([0-9a-f:]+)/i);
        if (match) result.bssid = match[1];
        return;
    }

    if (line.startsWith('freq:')) {
        const value = parseFloat(line.substring(5).trim());
        if (!Number.isNaN(value)) result.frequency = value;
        return;
    }

    if (line.startsWith('signal:')) {
        const match = line.match(/signal:\s*(-?\d+)/);
        if (match) result.signal = parseInt(match[1], 10);
    }
}

function parseBitrateLines(line, result) {
    if (line.startsWith('tx bitrate:')) {
        const bitrateInfo = parseBitrateLine(line);
        result.txBitrate = bitrateInfo.bitrate;
        applyBitrateInfoIfDetected(bitrateInfo, result);
        return;
    }

    if (line.startsWith('rx bitrate:')) {
        const bitrateInfo = parseBitrateLine(line);
        result.rxBitrate = bitrateInfo.bitrate;
        if (result.generation === WIFI_GENERATIONS.UNKNOWN) {
            applyBitrateInfoIfDetected(bitrateInfo, result);
        }
    }
}

function applyBitrateInfoIfDetected(bitrateInfo, result) {
    if (bitrateInfo.generation === WIFI_GENERATIONS.UNKNOWN) return;
    result.generation = bitrateInfo.generation;
    result.mcs = bitrateInfo.mcs;
    result.nss = bitrateInfo.nss;
    result.guardInterval = bitrateInfo.guardInterval;
    result.channelWidth = bitrateInfo.channelWidth;
}

function parseBitrateLine(line) {
    const bitrate = parseNumericValue(line, /(\d+\.?\d*)\s*MBit\/s/);
    const channelWidth = parseNumericValue(line, /(\d+)MHz/);
    const generationInfo = detectWifiGeneration(line);

    return {
        bitrate: bitrate,
        generation: generationInfo.generation,
        mcs: generationInfo.mcs,
        nss: generationInfo.nss,
        guardInterval: generationInfo.guardInterval,
        channelWidth: channelWidth,
    };
}

function parseNumericValue(line, pattern) {
    const match = line.match(pattern);
    if (!match) return null;
    const value = parseFloat(match[1]);
    return Number.isNaN(value) ? null : value;
}

function detectWifiGeneration(line) {
    return (
        tryParseEHT(line) ??
        tryParseHE(line) ??
        tryParseVHT(line) ??
        tryParseHT(line) ?? {
            generation: WIFI_GENERATIONS.UNKNOWN,
            mcs: null,
            nss: null,
            guardInterval: null,
        }
    );
}

function tryParseEHT(line) {
    if (!line.includes('EHT-MCS')) return null;
    return {
        generation: WIFI_GENERATIONS.WIFI_7,
        mcs: parseMcs(line, /EHT-MCS\s+(\d+)/),
        nss: parseNss(line, /EHT-NSS\s+(\d+)/),
        guardInterval: parseHeGuardInterval(line, 'EHT-GI'),
    };
}

function tryParseHE(line) {
    if (!line.includes('HE-MCS')) return null;
    return {
        generation: WIFI_GENERATIONS.WIFI_6,
        mcs: parseMcs(line, /HE-MCS\s+(\d+)/),
        nss: parseNss(line, /HE-NSS\s+(\d+)/),
        guardInterval: parseHeGuardInterval(line, 'HE-GI'),
    };
}

function tryParseVHT(line) {
    if (!line.includes('VHT-MCS')) return null;
    return {
        generation: WIFI_GENERATIONS.WIFI_5,
        mcs: parseMcs(line, /VHT-MCS\s+(\d+)/),
        nss: parseNss(line, /VHT-NSS\s+(\d+)/),
        guardInterval: line.includes('short GI') ? GUARD_INTERVALS.SHORT : GUARD_INTERVALS.NORMAL,
    };
}

function tryParseHT(line) {
    if (!line.match(/\bMCS\s+\d+/) || line.includes('-MCS')) return null;
    const mcs = parseMcs(line, /\bMCS\s+(\d+)/);
    return {
        generation: WIFI_GENERATIONS.WIFI_4,
        mcs: mcs,
        nss: mcs !== null ? Math.floor(mcs / 8) + 1 : null,
        guardInterval: line.includes('short GI') ? GUARD_INTERVALS.SHORT : GUARD_INTERVALS.NORMAL,
    };
}

function parseMcs(line, pattern) {
    return parseNumericValue(line, pattern);
}

function parseNss(line, pattern) {
    return parseNumericValue(line, pattern);
}

function parseHeGuardInterval(line, prefix) {
    const pattern = new RegExp(prefix + '\\s+(\\d+)');
    const match = line.match(pattern);
    if (!match) return GUARD_INTERVALS.NORMAL;
    const giIndex = parseInt(match[1], 10);
    return HE_GI_INDEX_MAP[giIndex] ?? GUARD_INTERVALS.NORMAL;
}

function parseIwScanDump(output) {
    const result = {};
    if (!output) return result;

    const bssBlocks = output.split(/^BSS /m);

    for (const block of bssBlocks) {
        const bssidMatch = block.match(/^([0-9a-f:]{17})/i);
        if (!bssidMatch) continue;
        const bssid = bssidMatch[1].toLowerCase();
        result[bssid] = detectScanGeneration(block);
    }

    return result;
}

function detectScanGeneration(block) {
    if (block.includes('EHT capabilities')) return WIFI_GENERATIONS.WIFI_7;
    if (block.includes('HE capabilities')) return WIFI_GENERATIONS.WIFI_6;
    if (block.includes('VHT capabilities') || block.includes('VHT operation')) return WIFI_GENERATIONS.WIFI_5;
    if (block.includes('HT capabilities') || block.includes('HT operation')) return WIFI_GENERATIONS.WIFI_4;
    return WIFI_GENERATIONS.UNKNOWN;
}

function getGenerationLabel(generation) {
    return isKnownGeneration(generation) ? `WiFi ${generation}` : 'WiFi';
}

function getGenerationDescription(generation) {
    return isKnownGeneration(generation)
        ? `WiFi ${generation} (${IEEE_STANDARDS[generation]})`
        : 'WiFi';
}

const GENERATION_ICON_FILENAMES = {
    [WIFI_GENERATIONS.WIFI_1]: 'wifi-1.svg',
    [WIFI_GENERATIONS.WIFI_2]: 'wifi-2.svg',
    [WIFI_GENERATIONS.WIFI_3]: 'wifi-3.svg',
    [WIFI_GENERATIONS.WIFI_4]: 'wifi-4.png',
    [WIFI_GENERATIONS.WIFI_5]: 'wifi-5.png',
    [WIFI_GENERATIONS.WIFI_6]: 'wifi-6.png',
    [WIFI_GENERATIONS.WIFI_7]: 'wifi-7.png',
    [WIFI_GENERATIONS.UNKNOWN]: null,
};

function getGenerationIconFilename(generation) {
    return GENERATION_ICON_FILENAMES[generation] ?? null;
}

// Signal quality helpers (ported from types.ts / wifiInfo.ts)
const SIGNAL_THRESHOLDS = { Excellent: -50, Good: -60, Fair: -70, Weak: -80 };
const SIGNAL_PERCENT_THRESHOLDS = { Excellent: 80, Good: 60, Fair: 40, Weak: 20 };
const SPEED_THRESHOLDS = { Excellent: 1000, VeryGood: 300, Good: 100, OK: 50, Weak: 20 };

function getSignalQuality(dbm) {
    if (dbm === null || dbm === undefined) return 'Unknown';
    if (dbm >= SIGNAL_THRESHOLDS.Excellent) return 'Excellent';
    if (dbm >= SIGNAL_THRESHOLDS.Good) return 'Good';
    if (dbm >= SIGNAL_THRESHOLDS.Fair) return 'Fair';
    if (dbm >= SIGNAL_THRESHOLDS.Weak) return 'Weak';
    return 'Poor';
}

function getSignalQualityFromPercent(pct) {
    if (pct >= SIGNAL_PERCENT_THRESHOLDS.Excellent) return 'Excellent';
    if (pct >= SIGNAL_PERCENT_THRESHOLDS.Good) return 'Good';
    if (pct >= SIGNAL_PERCENT_THRESHOLDS.Fair) return 'Fair';
    if (pct >= SIGNAL_PERCENT_THRESHOLDS.Weak) return 'Weak';
    return 'Poor';
}

function getSpeedQuality(bitrate) {
    if (bitrate >= SPEED_THRESHOLDS.Excellent) return 'Excellent';
    if (bitrate >= SPEED_THRESHOLDS.VeryGood) return 'VeryGood';
    if (bitrate >= SPEED_THRESHOLDS.Good) return 'Good';
    if (bitrate >= SPEED_THRESHOLDS.OK) return 'OK';
    if (bitrate >= SPEED_THRESHOLDS.Weak) return 'Weak';
    return 'Poor';
}

function frequencyToChannel(freq) {
    if (freq >= 2412 && freq <= 2484) {
        if (freq === 2484) return 14;
        return Math.round((freq - 2412) / 5) + 1;
    }
    if (freq >= 5170 && freq <= 5825) return Math.round((freq - 5000) / 5);
    if (freq >= 5955 && freq <= 7115) return Math.round((freq - 5950) / 5);
    return 0;
}

function frequencyToBand(freq) {
    if (freq >= 2400 && freq < 2500) return '2.4 GHz';
    if (freq >= 5150 && freq < 5900) return '5 GHz';
    if (freq >= 5925 && freq <= 7125) return '6 GHz';
    return 'Unknown';
}

function estimateSignalDbm(strengthPercent) {
    return -90 + (strengthPercent / 100) * 60;
}
