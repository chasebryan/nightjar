import Foundation

/// The Bluetooth SIG service-UUID registry,
/// entire: every adopted and member service
/// the SIG has assigned a short UUID, so an
/// advertisement naming a service can be
/// read even when no deeper decoder knows
/// the protocol. Generated 2026-10-18 from
/// the SIG assignments as mirrored by
/// Nordic Semiconductor's bluetooth-
/// numbers-database (76 short-UUID
/// entries; a handful of 128-bit custom
/// UUIDs in the source are not the SIG's
/// to assign and are not carried). Do not
/// hand-edit. The house's curated names in
/// Services.serviceNames still outrank
/// these wherever both exist.
///
/// Stored as packed text for the same
/// reason as CompanyRegistry: literals at
/// registry scale strain the type-checker;
/// text costs one parse, once.
enum ServiceRegistry {

    static let names: [UInt16: String] = {
        var out: [UInt16: String] = [:]
        for chunk in chunks {
            for line in chunk.split(
                    separator: "\n") {
                let parts = line.split(
                    separator: "\t",
                    maxSplits: 1)
                guard parts.count == 2,
                      let code = UInt16(
                        parts[0], radix: 16)
                else { continue }
                out[code] = String(parts[1])
            }
        }
        return out
    }()

    private static let chunks: [String] = [
        """
1800	Generic Access
1801	Generic Attribute
1802	Immediate Alert
1803	Link Loss
1804	Tx Power
1805	Current Time Service
1806	Reference Time Update Service
1807	Next DST Change Service
1808	Glucose
1809	Health Thermometer
180A	Device Information
180D	Heart Rate
180E	Phone Alert Status Service
180F	Battery Service
1810	Blood Pressure
1811	Alert Notification Service
1812	Human Interface Device
1813	Scan Parameters
1814	Running Speed and Cadence
1815	Automation IO
1816	Cycling Speed and Cadence
1818	Cycling Power
1819	Location and Navigation
181A	Environmental Sensing
181B	Body Composition
181C	User Data
181D	Weight Scale
181E	Bond Management Service
181F	Continuous Glucose Monitoring
1820	Internet Protocol Support Service
1821	Indoor Positioning
1822	Pulse Oximeter Service
1823	HTTP Proxy
1824	Transport Discovery
1825	Object Transfer Service
1826	Fitness Machine
1827	Mesh Provisioning Service
1828	Mesh Proxy Service
1829	Reconnection Configuration
183A	Insulin Delivery
183B	Binary Sensor
183C	Emergency Configuration
183E	Physical Activity Monitor
1843	Audio Input Control
1844	Volume Control
1845	Volume Offset Control
1846	Coordinated Set Identification
1847	Device Time
1848	Media Control
1849	Generic Media Control
184A	Constant Tone Extension
184B	Telephone Bearer
184C	Generic Telephone Bearer
184D	Microphone Control
184E	Audio Stream Control
184F	Broadcast Audio Scan
1850	Published Audio Capabilities
1851	Basic Audio Announcement
1852	Broadcast Audio Announcement
1853	Common Audio
1854	Hearing Access
1855	Telephony and Media Audio
1856	Public Broadcast Announcement
1857	Electronic Shelf Label
1858	Gaming Audio
1859	Mesh Proxy Solicitation
185B	Ranging Service (RAS)
1860	Tire Pressure Monitoring System Service
FCB2	Location Enabled Advertisement Service
FD0D	Blecon Advertising Service
FD6F	Exposure Notification Service
FE0F	Signify Netherlands B.V. (formerly Philips Lighting) Service
FE2C	Fast Pair Service
FE59	Secure DFU Service
FEAA	Eddystone
FEBB	File Transfer Service by Adafruit
        """
    ]
}
