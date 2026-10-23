import Combine
import Foundation

// MARK: - Totality
//
// The whole house, running at once, until
// it is stopped (Chase's commission,
// 2026-10-23): one word raises every
// standing system the house has — Serve
// up, the house tap recording,
// the listening post's ears already open
// by design — and a watchdog re-asserts
// each organ Totality itself raised, so
// the full and continuous test runs until
// `totality stop`, the console's stop, or
// the board's stop stands it down.
//
// Totality raises nothing of its own
// invention: every organ is the house's
// own, engaged through its own door, and
// every organ still answers to EMCON —
// an organ the Standard refuses is
// reported refused, never forced, and
// the watchdog will not re-light an organ
// the Standard has since forbidden (the
// Standard's own stand-down silences it;
// the watchdog only reconciles its flags
// to that reality). What Totality did not
// raise, Totality does not lower: an
// organ the operator already had running
// is left exactly as it was found.
//
// The mutation clause was declined at the
// commission and is not in this design:
// nothing here disguises the house from
// the wire or the router. The test runs
// in the open, as loud as its organs are.
//
// Totality raises no beacon and no flare
// (Chase's ruling, 2026-10-23): the air
// is not one of its organs. Nor does it
// loose Net-Assault (the same day's
// restructure, by the house's principles):
// the offensive arm belongs to the
// offensive commands — magdump's
// principle — not to the house simply
// standing. Net-Assault keeps its own
// doors: its room, and the banshee.

final class TotalityCenter: ObservableObject {

    static let shared = TotalityCenter()

    @Published private(set) var running = false
    @Published private(set) var startedAt: Date?
    /// Watchdog reconciliations since the
    /// run began — the run's pulse count.
    @Published private(set) var cycles = 0

    private weak var mouth: Mouth?
    private var timer: Timer?
    private var boardID: UUID?

    // What Totality itself raised — the
    // only things it may lower.
    private var startedServe = false
    private var tapWasOn = false

    private init() {}

    // MARK: Engage

    func engage(mouth: Mouth,
                say: @escaping (String) -> Void) {
        guard !running else {
            say(L("totality is already running — "
                  + "totality status tells it, "
                  + "totality stop stands it down."))
            return
        }
        self.mouth = mouth
        var raised: [String] = []

        // The tap first, so the run's own
        // raising is on the record.
        tapWasOn = BetafischTap.shared.enabled
        if !tapWasOn {
            BetafischTap.shared.enabled = true
            raised.append(L("the house tap, recording"))
        }

        // Serve, through its own door: the
        // Standard's gate is inside the
        // funnel, and the state read back is
        // the verdict.
        if mouth.serveRunning {
            say(L("Serve was already up — "
                  + "it is not Totality's to lower."))
        } else if EmconStandard.refused(.serveListed)
                    && EmconStandard.refused(.serveStealth) {
            say(String(format: L("Serve stays down — %@."),
                       EmconCondition.current.declared))
        } else {
            mouth.startServeFromSettings()
            startedServe = mouth.serveRunning
            if startedServe {
                raised.append(L("Serve, up"))
            } else {
                say(L("Serve would not rise — "
                      + "its own log in the Serve "
                      + "room says why."))
            }
        }

        guard !raised.isEmpty else {
            // Nothing could rise: leave the
            // tap as it was found and do not
            // call this a run.
            if !tapWasOn {
                BetafischTap.shared.enabled = false
            }
            say(L("totality engaged nothing — "
                  + "no organ could rise."))
            return
        }

        running = true
        startedAt = Date()
        cycles = 0
        boardID = ProcessBoard.shared.begin(
            label: L("Totality"), organ: "Totality",
            detail: L("the whole house, running"),
            announce: false,
            stop: {
                TotalityCenter.shared.standDown(
                    reason: L("stopped from the board"),
                    say: { _ in })
            })
        Journal.log("totality", "engaged",
                    "totality engaged — "
                    + raised.joined(separator: ", "))
        say(String(format: L("TOTALITY — the whole house is running: %@. The ears were already open. It runs until totality stop."),
                   raised.joined(separator: ", ")))
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: 20, repeats: true) {
                [weak self] _ in
                self?.watchdog()
            }
    }

    // MARK: The watchdog

    /// Re-assert what Totality raised, and
    /// reconcile the flags to the organs'
    /// true state — an organ the Standard
    /// has since forbidden is NOT re-lit
    /// (the Standard's stand-down silenced
    /// it); its flag is simply cleared, so
    /// the stand-down later lowers only
    /// what still stands as Totality's.
    private func watchdog() {
        guard running, let mouth else { return }
        cycles += 1
        if startedServe, !mouth.serveRunning {
            if EmconStandard.refused(.serveListed)
                && EmconStandard.refused(.serveStealth) {
                startedServe = false
            } else {
                mouth.startServeFromSettings()
                startedServe = mouth.serveRunning
            }
        }
    }

    // MARK: Stand down

    func standDown(reason: String,
                   say: @escaping (String) -> Void) {
        guard running else { return }
        timer?.invalidate()
        timer = nil
        let began = startedAt
        running = false
        startedAt = nil
        if let boardID {
            ProcessBoard.shared.end(boardID, .stopped)
            self.boardID = nil
        }
        var lowered: [String] = []
        if startedServe, let mouth, mouth.serveRunning {
            mouth.stopServe()
            lowered.append(L("Serve"))
        }
        startedServe = false
        if !tapWasOn, BetafischTap.shared.enabled {
            BetafischTap.shared.enabled = false
            lowered.append(L("the tap"))
        }
        let minutes = began.map {
            Int(Date().timeIntervalSince($0) / 60)
        } ?? 0
        Journal.log("totality", "stood down",
                    "totality stood down — "
                    + "\(cycles) watchdog cycles, "
                    + "\(minutes) min; lowered: "
                    + (lowered.isEmpty
                       ? "nothing of its own stood"
                       : lowered.joined(separator: ", ")))
        say(String(format: L("totality stood down — %lld watchdog cycle(s), %lld minute(s). Lowered: %@. Anything Totality did not raise is still standing."),
                   cycles, minutes,
                   lowered.isEmpty
                    ? L("nothing — its organs had already fallen or were the operator's own")
                    : lowered.joined(separator: ", ")))
    }

    // MARK: Status

    var statusLine: String {
        guard running else {
            return L("totality is not running.")
        }
        var organs: [String] = []
        if startedServe { organs.append("Serve") }
        if BetafischTap.shared.enabled {
            organs.append("tap")
        }
        let minutes = startedAt.map {
            Int(Date().timeIntervalSince($0) / 60)
        } ?? 0
        return String(format: L("totality is running — %lld minute(s), %lld watchdog cycle(s); its own organs up: %@."),
                      minutes, cycles,
                      organs.isEmpty
                        ? L("none standing")
                        : organs.joined(separator: ", "))
    }
}
