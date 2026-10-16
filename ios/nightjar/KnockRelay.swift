import Foundation

/// KnockRelay: the client half of an operator-run Knocktalk
/// relay (tools/knocktalk-relay in this repo — a small Python
/// rendezvous the operator hosts wherever they like).
///
/// Without a relay, Knocktalk is perimeter-only: one phone knocks
/// the other's LAN address, both must share a network. With one,
/// both phones knock the RELAY instead: the sender declares the
/// destination mailbox, knocks the sequence at the relay host,
/// and the receiver polls its mailbox and replays the sequence
/// into its own engine. The relay forwards port numbers and
/// nothing else — payloads stay sealed between the phones under
/// the pairing key, which the relay never holds. What the relay
/// can see is rendezvous metadata: mailbox names, timing, and
/// message lengths.
enum KnockRelay {
    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: "knocktalkRelayEnabled")
    }
    static var urlString: String {
        (UserDefaults.standard.string(forKey: "knocktalkRelayURL")
            ?? "").trimmingCharacters(in: .whitespaces)
    }
    static var token: String {
        UserDefaults.standard.string(forKey: "knocktalkRelayToken")
            ?? ""
    }
    static var mailbox: String {
        (UserDefaults.standard.string(forKey: "knocktalkRelayBox")
            ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// A relay peer is addressed as `relay:<mailbox>`.
    static let peerPrefix = "relay:"

    static func mailbox(ofPeer peer: String) -> String? {
        guard peer.hasPrefix(peerPrefix) else { return nil }
        return String(peer.dropFirst(peerPrefix.count))
    }

    /// Fully configured: switched on, with somewhere to knock
    /// and a mailbox of our own to be reached at.
    static var configured: Bool {
        enabled && baseURL != nil && !token.isEmpty
            && !mailbox.isEmpty && host != nil
    }

    static var baseURL: URL? {
        var raw = urlString
        if raw.isEmpty { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        while raw.hasSuffix("/") { raw.removeLast() }
        return URL(string: raw)
    }

    /// The host the knock stream is aimed at when the peer is a
    /// mailbox: the relay itself.
    static var host: String? { baseURL?.host }

    /// Tell the relay the next knock burst from this device is
    /// for `mailbox`. The declaration lives five minutes there;
    /// a message's frames each re-declare, so long conversations
    /// never ride a stale one.
    static func declare(to mailbox: String,
                        completion: @escaping (Bool) -> Void) {
        guard let base = baseURL else { completion(false); return }
        var request = URLRequest(
            url: base.appendingPathComponent("declare"))
        request.httpMethod = "POST"
        request.setValue("application/json",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["token": token, "from": self.mailbox,
                             "to": mailbox])
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    struct Frame: Decodable {
        let from: String
        let ports: [Int]
        let at: Double
    }

    /// Fetch and drain this phone's mailbox. Delivered frames
    /// are replayed into the knock engine by the chat layer.
    static func fetchInbox(
        completion: @escaping (Result<[Frame], Error>) -> Void) {
        guard let base = baseURL else {
            completion(.success([]))
            return
        }
        var components = URLComponents(
            url: base.appendingPathComponent("inbox"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "box", value: mailbox),
            URLQueryItem(name: "token", value: token),
        ]
        guard let url = components?.url else {
            completion(.success([]))
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            struct Reply: Decodable { let frames: [Frame] }
            let frames = data.flatMap {
                try? JSONDecoder().decode(Reply.self, from: $0)
            }?.frames ?? []
            DispatchQueue.main.async { completion(.success(frames)) }
        }.resume()
    }
}
