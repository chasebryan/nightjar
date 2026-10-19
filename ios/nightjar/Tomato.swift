import Foundation
import Combine

/// The tomato: a standing insult with teeth made
/// of attention. An operator can throw a tomato
/// at any device — by voice ("throw a tomato at
/// the printer") or from its row on the
/// Neighborhood board — and the mark persists
/// across launches. A marked device is picked on
/// in every test the house runs: Net-Assault
/// knocks it first in every pass and never skips
/// it as unchanged, sweeps report it wearing its
/// tomato, and it carries a 🍅 wherever it is
/// listed. The mark is an insult, not ordnance:
/// it changes who gets attention, never what a
/// test is allowed to do — every gate that held
/// before the tomato still holds with it on.
final class TomatoMarks: ObservableObject {

    static let shared = TomatoMarks()

    @Published private(set) var marked: Set<String> = []

    private static let key = "tomato.marks"

    init() {
        marked = Set(UserDefaults.standard
            .stringArray(forKey: Self.key) ?? [])
    }

    func isMarked(_ ip: String) -> Bool {
        marked.contains(ip)
    }

    func mark(_ ip: String) {
        marked.insert(ip)
        persist()
    }

    func unmark(_ ip: String) {
        marked.remove(ip)
        persist()
    }

    func clear() {
        marked.removeAll()
        persist()
    }

    /// The marked are cleared with the rest of the
    /// house when its defaults are restored.
    func forgetAll() {
        marked.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func persist() {
        UserDefaults.standard.set(Array(marked),
                                  forKey: Self.key)
    }

    /// How a marked address is named in speech:
    /// the operator's name for it where the board
    /// keeps one, else the bare address.
    func displayName(for ip: String,
                     store: NeighborhoodStore) -> String {
        store.neighbors.first { $0.ip == ip }?
            .displayName ?? ip
    }

    /// "the printer (192.168.4.1), the television
    /// (192.168.4.50)" — the whole marked cast,
    /// named as she would name them.
    func listing(store: NeighborhoodStore) -> String {
        marked.sorted().map {
            "\(displayName(for: $0, store: store)) (\($0))"
        }.joined(separator: ", ")
    }
}
