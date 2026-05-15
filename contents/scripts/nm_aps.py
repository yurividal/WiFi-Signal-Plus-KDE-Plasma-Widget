#!/usr/bin/env python3
"""
WiFi Signal Plus — NM access point scanner.

Uses the NM D-Bus API to get all visible access points with their full
properties — the same API that the GNOME extension uses internally via
NM.DeviceWifi.get_access_points() + NM.AccessPoint.get_*().

Outputs a JSON array to stdout.  On any error, outputs '[]'.
"""
import dbus
import json
import sys

# AP security flag values (mirror of GNOME extension's AP_SECURITY constants)
AP_KEY_MGMT_PSK    = 0x100
AP_KEY_MGMT_802_1X = 0x200
AP_KEY_MGMT_SAE    = 0x400

NM_DEVICE_TYPE_WIFI = 2


def get_security(wpa_flags: int, rsn_flags: int) -> str:
    if rsn_flags & AP_KEY_MGMT_SAE:
        return 'WPA3'
    if rsn_flags & AP_KEY_MGMT_802_1X:
        return 'WPA2-Enterprise'
    if rsn_flags & AP_KEY_MGMT_PSK:
        return 'WPA2'
    if wpa_flags & AP_KEY_MGMT_802_1X:
        return 'WPA-Enterprise'
    if wpa_flags & AP_KEY_MGMT_PSK:
        return 'WPA'
    return 'Open'


def main() -> None:
    bus = dbus.SystemBus()
    nm_obj = bus.get_object(
        'org.freedesktop.NetworkManager',
        '/org/freedesktop/NetworkManager',
    )
    nm_props = dbus.Interface(nm_obj, 'org.freedesktop.DBus.Properties')
    devices = list(nm_props.Get('org.freedesktop.NetworkManager', 'AllDevices'))

    result = []

    for dev_path in devices:
        dev_obj = bus.get_object('org.freedesktop.NetworkManager', str(dev_path))
        dev_p = dbus.Interface(dev_obj, 'org.freedesktop.DBus.Properties')
        try:
            dev_type = int(dev_p.Get(
                'org.freedesktop.NetworkManager.Device', 'DeviceType',
            ))
            if dev_type != NM_DEVICE_TYPE_WIFI:
                continue

            iface = str(dev_p.Get(
                'org.freedesktop.NetworkManager.Device', 'Interface',
            ))
            wifi_iface = dbus.Interface(
                dev_obj,
                'org.freedesktop.NetworkManager.Device.Wireless',
            )
            ap_paths = list(wifi_iface.GetAllAccessPoints())

            for ap_path in ap_paths:
                try:
                    ap_obj = bus.get_object(
                        'org.freedesktop.NetworkManager', str(ap_path),
                    )
                    ap_p = dbus.Interface(ap_obj, 'org.freedesktop.DBus.Properties')
                    props = ap_p.GetAll(
                        'org.freedesktop.NetworkManager.AccessPoint',
                    )

                    ssid_bytes = bytes(props.get('Ssid', []))
                    ssid = ssid_bytes.decode('utf-8', errors='replace')
                    if not ssid:
                        continue

                    rsn = int(props.get('RsnFlags', 0))
                    wpa = int(props.get('WpaFlags', 0))

                    result.append({
                        'bssid':      str(props.get('HwAddress', '')).lower(),
                        'ssid':       ssid,
                        'iface':      iface,
                        'frequency':  int(props.get('Frequency', 0)),
                        'maxBitrate': int(props.get('MaxBitrate', 0)) // 1000,
                        'bandwidth':  int(props.get('Bandwidth', 20)),
                        'strength':   int(props.get('Strength', 0)),
                        'security':   get_security(wpa, rsn),
                        'lastSeen':   int(props.get('LastSeen', 0)),
                    })
                except dbus.DBusException:
                    pass
        except dbus.DBusException:
            pass

    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('[]')
        sys.exit(1)
