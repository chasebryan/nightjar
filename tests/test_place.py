import unittest

from nightjar.place import current_place

AIRPORT = """     aguCtlRSSI: -52
          state: running
        BSSID: aa:bb:cc:dd:ee:ff
         SSID: HomeNet
        channel: 6
"""

IPCONFIG = """en0: flags=8863<UP>
	SSID : CoffeeShop
	BSSID : 11:22:33:44:55:66
"""

NETSH = """    SSID                   : OfficeWifi
    BSSID                  : 22:33:44:55:66:77
"""

SYSTEM_PROFILER = """Wi-Fi:

      Wi-Fi Information:
          Current Network Information:
            Attic Net:
              PHY Mode: 802.11ax
              Channel: 36 (5GHz, 80MHz)
          Other Local Wi-Fi Networks:
            Neighbour:
              PHY Mode: 802.11n
"""

IW = """phy#0
	Interface wlan0
		ifindex 3
		type managed
		ssid Workshop
"""


def runner(mapping):
    def run(argv):
        for key, text in mapping.items():
            if key in " ".join(argv):
                return text
        return ""
    return run


class PlaceTests(unittest.TestCase):
    def test_macos_airport(self):
        place = current_place(runner=runner({"airport": AIRPORT}),
                              platform="darwin")
        self.assertEqual(place, "HomeNet (aa:bb:cc:dd:ee:ff)")

    def test_macos_falls_back_to_ipconfig(self):
        place = current_place(
            runner=runner({"airport": "", "ipconfig": IPCONFIG}),
            platform="darwin")
        self.assertEqual(place, "CoffeeShop (11:22:33:44:55:66)")

    def test_macos_falls_back_to_system_profiler(self):
        place = current_place(
            runner=runner({"system_profiler": SYSTEM_PROFILER}),
            platform="darwin")
        self.assertEqual(place, "Attic Net")

    def test_macos_redacted_is_no_place(self):
        redacted = AIRPORT.replace("HomeNet", "<redacted>")
        place = current_place(
            runner=runner({"airport": redacted, "ipconfig": "",
                           "networksetup": "You are not associated"}),
            platform="darwin")
        self.assertIsNone(place)

    def test_linux_nmcli(self):
        place = current_place(
            runner=runner({"nmcli": "no:Other\nyes:HomeNet\n"}),
            platform="linux")
        self.assertEqual(place, "HomeNet")

    def test_linux_nmcli_keeps_colons_in_ssids(self):
        place = current_place(
            runner=runner({"nmcli": "yes:Cafe:Upstairs\n"}),
            platform="linux")
        self.assertEqual(place, "Cafe:Upstairs")

    def test_linux_falls_back_to_iw(self):
        place = current_place(runner=runner({"iw dev": IW}), platform="linux")
        self.assertEqual(place, "Workshop")

    def test_windows_netsh(self):
        place = current_place(runner=runner({"netsh": NETSH}),
                              platform="win32")
        self.assertEqual(place, "OfficeWifi (22:33:44:55:66:77)")

    def test_missing_tools_mean_no_place(self):
        def boom(argv):
            raise FileNotFoundError(argv[0])
        self.assertIsNone(current_place(runner=boom, platform="darwin"))

    def test_unknown_platform(self):
        self.assertIsNone(current_place(runner=runner({}), platform="plan9"))


if __name__ == "__main__":
    unittest.main()
