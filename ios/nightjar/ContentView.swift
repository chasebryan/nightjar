import Combine
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The tab beat, in two independent parts.
///
/// The tab part keys on the one event every
/// road into a tab must produce: its content
/// appearing on screen. Selection writes are
/// invisible to half the roads (the More list
/// resolves inside UIKit and never writes
/// through SwiftUI — the flight recorder
/// proved it), but a tab the operator is
/// looking at has appeared. Each appearance
/// answers with a press-strength beat deferred
/// a fraction past the transition's opening
/// frame, where the haptic engine drops
/// requests; the first appearance after
/// launch only primes (no beat for the tab
/// the house reopens on). This part keeps no
/// state beyond the current tab, deliberately:
/// a coalesced register that settled bursts
/// into states desynced after a few trips
/// through the More stack — appearance events
/// there arrive with extras and reordering,
/// and a register that trusts the last event
/// ends up swallowing real changes as "no
/// change". Dumb and independent wins.
///
/// The list part covers the two roads that
/// end on the system's own More list, where
/// no tab appears: the More button's tap (the
/// current tab is covered and vanishes) and
/// the back chevron's pop (the section's tab
/// is removed and vanishes). A vanish that no
/// appearance follows within a breath is one
/// of those two, and it earns the same beat —
/// additively only: this path can add a beat,
/// never take one away.
enum TabBeat {
    private static var primed = false
    private static var current: Int?
    private static var sequence = 0
    /// The transition whose beat has already
    /// spoken. Every press path claims its
    /// transition before firing, so one
    /// navigation can never be beaten twice —
    /// the old guard trusted event ORDER (a
    /// vanish timer stood down only when an
    /// appearance followed it), and on the
    /// transitions where the appearance landed
    /// FIRST, both timers fired, spaced right
    /// at the haptics fold's edge: the two
    /// taps the operator kept reporting.
    private static var answered = 0

    /// Claim a transition's one beat. Main
    /// queue only, like every caller here.
    private static func beatIfUnclaimed(
        _ token: Int) -> Bool {
        if answered == token { return false }
        answered = token
        return true
    }

    static func appeared(_ tag: Int) {
        sequence += 1
        let mine = sequence
        current = tag
        if !primed {
            primed = true
            return
        }
        DevLog.event("tab", "\(tag) (appeared)")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.15) {
            if current == tag,
               beatIfUnclaimed(mine) {
                Haptics.press()
            }
        }
    }

    /// Another authority (the selection watch)
    /// has answered for this navigation: bump
    /// the sequence so a pending vanish timer
    /// stands down instead of doubling the beat.
    /// Returns the new sequence — the watch's
    /// own timer claims that token, so its
    /// beat and any other path's cannot both
    /// land for the same tap.
    @discardableResult
    static func noteExternalBeat() -> Int {
        sequence += 1
        return sequence
    }

    /// The watch's timer asks here before it
    /// presses, like every other path.
    static func claimWatchBeat(_ token: Int) -> Bool {
        beatIfUnclaimed(token)
    }

    static func vanished(_ tag: Int) {
        var mine = sequence
        if current == tag, answered == sequence {
            // A fresh act on a landing already
            // beaten — the More list's back pop,
            // where nothing appears to answer.
            // Claim a fresh token for it now; a
            // later bump (the selection watch
            // tripping, a successor appearing)
            // still stands this timer down.
            sequence += 1
            mine = sequence
        }
        let token = mine
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.35) {
            // A successor appeared after this
            // vanish — a plain tab change, whose
            // appearance already answered. Only
            // a vanish still unanswered at this
            // distance is the More list's.
            guard sequence == token,
                  beatIfUnclaimed(token)
            else { return }
            Haptics.press()
            DevLog.event(
                "tab", "more list (vanish \(tag))")
        }
    }
}

/// The selection watch: a passive ear on the
/// tab bar controller's selected controller —
/// a stored property, observed reliably, where
/// a navigation stack's contents were not.
/// One transition matters: the selected
/// controller BECOMING the More navigation
/// controller, which is the More button's tap
/// itself. It fires on every tap, first or
/// fiftieth — unlike the appearance signals
/// around the More stack, which arrive with
/// extras and omissions once that stack
/// exists (the first More tap beat, and later
/// ones went silent, for exactly that reason).
/// Row picks and back pops keep the More
/// controller selected, so they never trip
/// this watch; TabBeat's own paths own them.
/// When this watch answers, it bumps TabBeat's
/// sequence, standing the vanish timer down
/// so the tap is never beaten twice.
#if os(iOS)
enum SelectionWatch {
    private static var observation:
        NSKeyValueObservation?
    private static var installed = false
    private static var attempts = 0

    static func install(from view: UIView) {
        guard !installed,
              let window = view.window else {
            retry(from: view)
            return
        }
        guard let bar = findTabBar(in: window)
        else {
            retry(from: view)
            return
        }
        installed = true
        let more = bar.moreNavigationController
        observation = bar.observe(
            \.selectedViewController,
            options: [.new, .old]
        ) { controller, change in
            let now = change.newValue ?? nil
            let was = change.oldValue ?? nil
            guard now === more, was !== more
            else { return }
            let token = TabBeat.noteExternalBeat()
            DevLog.event("tab",
                         "more opened (watch)")
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.15) {
                if controller.selectedViewController
                    === more,
                   TabBeat.claimWatchBeat(token) {
                    Haptics.press()
                }
            }
        }
        DevLog.event("tab", "selection watch on")
    }

    /// The tab bar controller is not reachable
    /// at the first attempt in every launch
    /// order; a few patient retries land it.
    private static func retry(from view: UIView) {
        guard !installed, attempts < 10 else {
            return
        }
        attempts += 1
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.4) {
            install(from: view)
        }
    }

    /// Find the tab bar in the window's view
    /// tree, then climb its responder chain to
    /// the controller that owns it.
    private static func findTabBar(
        in window: UIWindow) -> UITabBarController? {
        guard let tabBar = firstTabBar(in: window)
        else { return nil }
        var responder: UIResponder? = tabBar
        while let r = responder {
            if let bar = r as? UITabBarController {
                return bar
            }
            responder = r.next
        }
        return nil
    }

    private static func firstTabBar(
        in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar {
            return bar
        }
        for sub in view.subviews {
            if let bar = firstTabBar(in: sub) {
                return bar
            }
        }
        return nil
    }
}

/// A zero-size representable whose only job is
/// to be in the window, so the selection watch
/// can install itself from real UIKit ground.
struct TabProbe: UIViewRepresentable {
    func makeUIView(
        context: Context) -> ProbeView {
        ProbeView()
    }

    func updateUIView(_ uiView: ProbeView,
                      context: Context) {}

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                SelectionWatch.install(from: self)
            }
        }
    }
}

#endif

#if os(macOS)
/// On the Mac there is no tab bar controller for a
/// selection watch to ride — the strip is the
/// system's own, and a selection is just a
/// selection. The probe is an empty view.
struct TabProbe: View {
    var body: some View { Color.clear }
}
#endif

struct ContentView: View {
    @EnvironmentObject private var toasts: ToastCenter
    @ObservedObject private var board = ProcessBoard.shared
    @State private var showBoard = false
    /// The Mac detail's mounted rooms (fix264):
    /// a room is built on its first visit and
    /// kept alive after, so switching panes
    /// never loses a room's work.
    @State private var visitedRooms: Set<Int> = []
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var emcon: Emcon
    @EnvironmentObject private var post: ListeningPost
    @State private var tab: Int
    @State private var showBoot = true
    /// Serve's sheet at the shell level (iOS):
    /// raised when a house navigation names
    /// Serve — the console's `open serve`, her
    /// "take me to serve" — now that Serve
    /// lives under Sessions (Chase's order,
    /// 2026-10-22) instead of on the bar.
    @State private var showServe = false
    @State private var showLanguageWelcome = false
    @ObservedObject private var languageCenter =
        LanguageCenter.shared
    @AppStorage(BootMedia.enabledKey)
    private var bootEnabled = true

    init() {
        // The house reopens where you left it:
        // the last tab worked in is restored on
        // launch, even after a swipe-close, so
        // work continues where it stopped.
        let stored = UserDefaults.standard
            .object(forKey: "house.lastTab") as? Int
        // Every tag the tab view below declares. This
        // set must name them all: a clamp narrower than
        // the house silently drops the sections past
        // it on relaunch — Macros, tag 10, was lost to
        // a 0...9 clamp the day it landed, and the app
        // reopened on Listen instead of where the
        // operator had been working.
        // (Serve's old 2 is gone on purpose:
        // it is not a phone tab any more, so a
        // stored 2 falls back to Listen rather
        // than restoring a room that is not on
        // the bar. Onion's 13 joins the set —
        // it was missing, the very failure this
        // comment describes.)
        let knownTabs: Set<Int> =
            [9, 0, 1, 12, 5, 3, 4, 6, 7, 8, 10, 11, 13]
        _tab = State(initialValue:
            stored.flatMap {
                knownTabs.contains($0) ? $0 : nil
            } ?? 0)
    }
    @ObservedObject private var themes = ThemeCenter.shared

    /// The house's rooms on the phone: the tab
    /// strip, each room a tab, everything hung
    /// on the shell below.
    private var phoneShell: some View {
        TabView(selection: $tab) {
        SkelliView()
            .appThemed(.skelli)
            .tabItem { Label(L("Skelli"),
                             systemImage: "brain.head.profile") }
            .tag(9)
            .onAppear { TabBeat.appeared(9) }
            .onDisappear { TabBeat.vanished(9) }
        ListenView(tab: $tab)
            .appThemed(.listen)
            .tabItem { Label(L("Listen"), systemImage: "dot.radiowaves.left.and.right") }
            .tag(0)
            .onAppear { TabBeat.appeared(0) }
            .onDisappear { TabBeat.vanished(0) }
        // The console sits right in the middle
        // of the main bar (Chase's order,
        // 2026-10-22): Skelli, Listen, Blacksite,
        // Send — then More. Serve is not on the
        // bar any more; it lives under Sessions,
        // raised as a sheet from there (and by
        // any house navigation that names it).
        BlacksiteView()
            .appThemed(.blacksite)
            .tabItem { Label(L("Blacksite"),
                             systemImage: "terminal.fill") }
            .tag(12)
            .onAppear { TabBeat.appeared(12) }
            .onDisappear { TabBeat.vanished(12) }
        SendView()
            .appThemed(.send)
            .tabItem { Label(L("Send"), systemImage: "paperplane") }
            .tag(1)
            .onAppear { TabBeat.appeared(1) }
            .onDisappear { TabBeat.vanished(1) }
        // Declaration order past the bar is the
        // More list's order: About heads it — it
        // is the app's identity and its options
        // hub — and Sessions sits under it.
        // Tags are unchanged by position.
        AboutView()
            .appThemed(.about)
            .tabItem { Label(L("About"), systemImage: "info.circle") }
            .tag(5)
            .onAppear { TabBeat.appeared(5) }
            .onDisappear { TabBeat.vanished(5) }
        SessionsView()
            .appThemed(.sessions)
            .tabItem { Label(L("Sessions"), systemImage: "list.bullet.rectangle") }
            .tag(3)
            .onAppear { TabBeat.appeared(3) }
            .onDisappear { TabBeat.vanished(3) }
        ScanView(tab: $tab)
            .appThemed(.scan)
            .tabItem { Label(L("Scan"), systemImage: "scope") }
            .tag(4)
            .onAppear { TabBeat.appeared(4) }
            .onDisappear { TabBeat.vanished(4) }
        ReconBenchView(tab: $tab)
            .appThemed(.recon)
            .tabItem { Label(L("Recon"), systemImage: "target") }
            .tag(6)
            .onAppear { TabBeat.appeared(6) }
            .onDisappear { TabBeat.vanished(6) }
        EmconView()
            .appThemed(.emcon)
            .tabItem {
                // The bare "shield.slash" name renders
                // as nothing on the operator's symbol
                // set; the base shield with the slash
                // variant asked for explicitly degrades
                // to a visible shield, never a blank.
                Label(L("EMCON"), systemImage: "shield")
                    .symbolVariant(.slash)
            }
            .tag(7)
            .onAppear { TabBeat.appeared(7) }
            .onDisappear { TabBeat.vanished(7) }
        KnockChatView()
            .appThemed(.knocktalk)
            .tabItem { Label(L("Knocktalk"),
                             systemImage: "message.badge.waveform") }
            .tag(8)
            .onAppear { TabBeat.appeared(8) }
            .onDisappear { TabBeat.vanished(8) }
        MacrosView()
            .appThemed(.macros)
            .tabItem { Label(L("Macros"),
                             systemImage: "puzzlepiece.extension.fill") }
            .tag(10)
            .onAppear { TabBeat.appeared(10) }
            .onDisappear { TabBeat.vanished(10) }
        CryptoView()
            .appThemed(.vault)
            .tabItem { Label(L("Vault"),
                             systemImage: "lock.fill") }
            .tag(11)
            .onAppear { TabBeat.appeared(11) }
            .onDisappear { TabBeat.vanished(11) }
        OnionView()
            .appThemed(.onion)
            .tabItem { Label(L("Onion"),
                             systemImage: "circle.circle") }
            .tag(13)
            .onAppear { TabBeat.appeared(13) }
            .onDisappear { TabBeat.vanished(13) }
        }
    }

#if os(macOS)
    /// One room of the Mac's detail pane
    /// (fix264), mounted on its first visit
    /// and kept alive after: a Mac operator
    /// switches panes, and a pane does not
    /// lose its work for being looked away
    /// from — the console's session, the
    /// Send room's typed target. Hidden
    /// panes take no touches and stay
    /// silent for VoiceOver.
    @ViewBuilder
    private func macRoom(_ tag: Int) -> some View {
        if visitedRooms.contains(tag) {
            Group {
                if tag == 9 {
                    AnyView(SkelliView()
                        .appThemed(.skelli))
                } else if tag == 0 {
                    AnyView(ListenView(tab: $tab)
                        .appThemed(.listen))
                } else if tag == 1 {
                    AnyView(SendView()
                        .appThemed(.send))
                } else if tag == 2 {
                    AnyView(ServeView()
                        .appThemed(.serve))
                } else if tag == 5 {
                    AnyView(AboutView()
                        .appThemed(.about))
                } else if tag == 12 {
                    AnyView(BlacksiteView()
                        .appThemed(.blacksite))
                } else if tag == 3 {
                    AnyView(SessionsView()
                        .appThemed(.sessions))
                } else if tag == 4 {
                    AnyView(ScanView(tab: $tab)
                        .appThemed(.scan))
                } else if tag == 6 {
                    AnyView(ReconBenchView(tab: $tab)
                        .appThemed(.recon))
                } else if tag == 7 {
                    AnyView(EmconView()
                        .appThemed(.emcon))
                } else if tag == 8 {
                    AnyView(KnockChatView()
                        .appThemed(.knocktalk))
                } else if tag == 10 {
                    AnyView(MacrosView()
                        .appThemed(.macros))
                } else if tag == 11 {
                    AnyView(CryptoView()
                        .appThemed(.vault))
                } else if tag == 13 {
                    AnyView(OnionView()
                        .appThemed(.onion))
                }
            }
            .macRoomVisible(tab == tag)
        }
    }

    /// The Mac's navigator (fix264): a native
    /// split view — a sidebar of rooms, the
    /// room itself as the detail. A Mac app's
    /// window is a sidebar and a pane, and the
    /// toolbar belongs to the pane: the room's
    /// own title stands there once, the way
    /// Mail and Settings are built. (fix261 put
    /// a title of its own on the tab view's
    /// toolbar while every room's stack claimed
    /// the same bar — two titles, one of them
    /// floating over the content.)
    private var macShell: some View {
        NavigationSplitView {
            List(selection: $tab) {
                Section {
                    Label(L("Skelli"),
                          systemImage: "brain.head.profile")
                        .tag(9)
                    Label(L("Listen"),
                          systemImage: "dot.radiowaves.left.and.right")
                        .tag(0)
                    Label(L("Send"),
                          systemImage: "paperplane")
                        .tag(1)
                    Label(L("Serve"),
                          systemImage: "tray.and.arrow.down")
                        .tag(2)
                }
                Section {
                    Label(L("Blacksite"),
                          systemImage: "terminal.fill")
                        .tag(12)
                    Label(L("Sessions"),
                          systemImage: "list.bullet.rectangle")
                        .tag(3)
                    Label(L("Scan"),
                          systemImage: "scope")
                        .tag(4)
                    Label(L("Recon"),
                          systemImage: "target")
                        .tag(6)
                    Label(L("EMCON"),
                          systemImage: "shield")
                        .symbolVariant(.slash)
                        .tag(7)
                    Label(L("Knocktalk"),
                          systemImage: "message.badge.waveform")
                        .tag(8)
                    Label(L("Macros"),
                          systemImage: "puzzlepiece.extension.fill")
                        .tag(10)
                    Label(L("Vault"),
                          systemImage: "lock.fill")
                        .tag(11)
                    Label(L("Onion"),
                          systemImage: "circle.circle")
                        .tag(13)
                }
                Section {
                    Label(L("About"),
                          systemImage: "info.circle")
                        .tag(5)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: 200, ideal: 232, max: 300)
        } detail: {
            ZStack {
                macRoom(9)
                macRoom(0)
                macRoom(1)
                macRoom(2)
                macRoom(5)
                macRoom(12)
                macRoom(3)
                macRoom(4)
                macRoom(6)
                macRoom(7)
                macRoom(8)
                macRoom(10)
                macRoom(11)
                macRoom(13)
            }
        }
        .onAppear { visitedRooms.insert(tab) }
        .onChange(of: tab) { newTab in
            visitedRooms.insert(newTab)
            TabBeat.appeared(newTab)
        }
    }
#endif

    /// The shell both platforms hang their
    /// house on: the navigator (the phone's
    /// tab strip, the Mac's split view), its
    /// tint, its watches, its overlays and
    /// its sheets.
    private var tabShell: some View {
        Group {
#if os(macOS)
            macShell
#else
            phoneShell
#endif
        }
        .tint(themes.current.accent)
        .macShellBar(processes: board.active.count) {
            showBoard = true
        }
#if os(iOS)
        .sheet(isPresented: $showServe) {
            ServeView()
                .appThemed(.serve)
        }
#endif
    .onReceive(
        NotificationCenter.default.publisher(
            for: Blacksite.openTabNotification)
    ) { note in
        if let tag = note.userInfo?["tag"]
            as? Int {
#if os(iOS)
            if tag == 2 {
                // Serve lives under Sessions
                // now: land there with its
                // sheet raised.
                tab = 3
                showServe = true
            } else {
                tab = tag
            }
#else
            tab = tag
#endif
        }
    }
    .onAppear {
        // The specialist gets the house's real
        // organs, so its hands work the real
        // controls.
        SkelliCenter.shared.wire(mouth: mouth,
                                 emcon: emcon,
                                 post: post)
        ProcessBoard.shared.toasts = toasts
    }
    .onReceive(NotificationCenter.default.publisher(
        for: .houseNavigate)) { note in
        if let target = note.userInfo?["tab"] as? Int {
#if os(iOS)
            if target == 2 {
                tab = 3
                showServe = true
            } else {
                tab = target
            }
#else
            tab = target
#endif
        }
    }
    .onReceive(NotificationCenter.default.publisher(
        for: .houseReplayBoot)) { _ in
        // The developer bench's party trick:
        // run the ceremony again without
        // relaunching the house.
        showBoot = true
    }
    .onChange(of: tab) { newTab in
        UserDefaults.standard.set(
            newTab, forKey: "house.lastTab")
    }
    .onChange(of: mouth.reconHandoff) { handoff in
        // Counter-knock pivot: a tripwire row tapped in EMCON
        // lands the operator on the Recon bench, pre-aimed.
        if handoff != nil { tab = 6 }
    }
    .overlay {
        // Zero-size and touch-transparent:
        // the probe that installs the
        // selection watch.
        TabProbe()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }
    .overlay(alignment: .top) {
        VStack(spacing: 8) {
            if let toast = toasts.current {
                ToastView(toast: toast)
                    .transition(.move(edge: .top)
                        .combined(with: .opacity))
            }
            if !board.active.isEmpty {
                ProcessStripView(board: board) {
                    showBoard = true
                }
                .transition(.move(edge: .top)
                    .combined(with: .opacity))
            }
        }
        .padding(.top, 6)
        .animation(.spring(response: 0.35,
                           dampingFraction: 0.85),
                   value: board.active.count)
    }
    .sheet(isPresented: $showBoard) {
        ProcessBoardView()
    }
    }

    var body: some View {
        ZStack {
            AppBackdrop()
            if showBoot && bootEnabled {
                BootView {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showBoot = false
                    }
                    // The one-time welcome: the
                    // boot lifts, and a new user's
                    // first act in the house is
                    // choosing its tongue.
                    if !languageCenter.welcomed {
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + 0.6) {
                            showLanguageWelcome = true
                        }
                    }
                }
                .transition(.opacity)
                .zIndex(20)
            } else {
                // The house takes its place only
                // once the ceremony lifts: while
                // the boot runs, no part of it —
                // no navigator, no room — stands
                // in the hierarchy to be tapped
                // before everything is ready.
                tabShell
            }
        }
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            if !bootEnabled && !languageCenter.welcomed {
                showLanguageWelcome = true
            }
        }
        .sheet(isPresented: $showLanguageWelcome,
               onDismiss: {
                   LanguageCenter.shared.markWelcomed()
               }) {
            LanguageSheet(welcome: true)
        }
    }
}

// MARK: - Listen

struct ListenView: View {
    @Binding var tab: Int
    @EnvironmentObject private var post: ListeningPost
#if !STORE_BUILD
    @EnvironmentObject private var updater: UpdateChecker
#endif
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @ObservedObject private var drive =
        WardriveCenter.shared
    @State private var label = ""
    @State private var huntRow: DeviceRow?
    @State private var wardriveSheet = false
    @State private var now = Date().timeIntervalSince1970

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
#if !STORE_BUILD
                if let release = updater.visibleUpdate {
                    Section {
                        UpdateBanner(release: release)
                    }
                }
#endif
#if os(macOS)
                if let session = post.session {
                    Section {
                        // The Mac dashboard (fix261):
                        // the session at a glance,
                        // as tiles over the detail.
                        HStack(spacing: 10) {
                            macStatTile(
                                value: "\(post.deviceCount)",
                                label: L("In earshot"))
                            macStatTile(
                                value: "\(post.sightingCount)",
                                label: L("Sightings"))
                            macStatTile(
                                value: elapsed(
                                    since: session.startedAt),
                                label: bluetoothText)
                        }
                        .listRowInsets(EdgeInsets(
                            top: 6, leading: 0,
                            bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
#endif
                Section {
                    statusRow
                    if let session = post.session {
                        runningRows(session)
                    } else {
                        idleRows
                    }
                }
                Section {
                    NavigationLink {
                        SigintStationView()
                    } label: {
                        Label(L("SIGINT Station — the fused picture"),
                              systemImage:
                                "antenna.radiowaves.left.and.right")
                    }
                    Text(L("Everything this phone can hear — the air, the wire, the Night log — in one registry, one timeline, recorded watches."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        Haptics.tap()
                        wardriveSheet = true
                    } label: {
                        Label(L("War Driving — the survey log"),
                              systemImage: "car")
                    }
                    if drive.running {
                        Text(String(format: L("Rolling — %lld devices · %lld networks"),
                                    Int64(drive.uniqueDevices),
                                    Int64(drive.uniqueNetworks)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(L("Take the post for a drive: every device it hears and every network you join, written to a log as you move."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if post.isListening || !post.rows.isEmpty {
                    Section(header: Text(post.isListening ? L("In earshot") : L("Last session"))) {
                        if post.rows.isEmpty {
                            Text(L("Listening… nothing heard yet."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(post.rows) { row in
                            NavigationLink {
                                DeviceDetailView(row: row, tab: $tab)
                            } label: {
                                DeviceRowView(row: row, now: now)
                            }
                                .contextMenu {
                                    Button {
                                        if let id = UUID(uuidString: row.id) {
                                            let name = row.preferredLabel
                                                ?? row.kind
                                            mouth.requestWrite(to: id,
                                                               label: name)
                                            Haptics.select()
                                            toasts.show(String(format: L("Write target set: %@ — Send tab"), name))
                                            tab = 1
                                        }
                                    } label: {
                                        Label(L("Write a payload…"),
                                              systemImage: "paperplane")
                                    }
                                    Button {
                                        huntRow = row
                                    } label: {
                                        Label(L("Hunt this signal"),
                                              systemImage: "location.viewfinder")
                                    }
                                }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .macColumn(880)
            .macListStyle()
            .background { AppBackdrop() }
            .navigationTitle(L("nightjar"))
            .onReceive(clock) { _ in now = Date().timeIntervalSince1970 }
            .sheet(item: $huntRow) { row in
                HuntView(targetID: row.id)
                    .environmentObject(post)
            }
            .sheet(isPresented: $wardriveSheet) {
                WardriveView()
                    .environmentObject(post)
            }
        }
    }

    /// One dashboard tile (Mac, fix261): a big
    /// number over a small caption, in the panel
    /// dress.
    private func macStatTile(value: String,
                             label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity,
               alignment: .leading)
        .padding(10)
        .macPanel()
    }

    @ViewBuilder private var statusRow: some View {
        HStack {
            Image(systemName: bluetoothSymbol)
                .foregroundStyle(post.bluetoothState == .poweredOn ? Color.green : Color.orange)
            Text(bluetoothText)
            Spacer()
            if post.inBackground {
                Text(L("background")).font(.caption).foregroundStyle(.secondary)
            }
        }
        if let error = post.lastError {
            Text(error).font(.footnote).foregroundStyle(.red)
        }
    }

    @ViewBuilder private var idleRows: some View {
        TextField(L("Place label (optional, e.g. home)"), text: $label)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        Button {
            Haptics.tap()
            post.start(label: label)
        } label: {
            Label(L("Start listening"), systemImage: "play.circle.fill")
        }
        .disabled(post.bluetoothState != .poweredOn)
    }

    @ViewBuilder private func runningRows(_ session: ListeningPost.ActiveSession) -> some View {
        HStack {
            Text(session.label.map { "@ \($0)" } ?? "unlabeled session")
            Spacer()
            Text(elapsed(since: session.startedAt))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        HStack {
            Text(String(format: L("%lld addresses · %lld sightings"), post.deviceCount, post.sightingCount))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        Button(role: .destructive) {
            Haptics.tap()
            post.stop()
        } label: {
            Label(L("Stop and save"), systemImage: "stop.circle.fill")
        }
    }

    private var bluetoothSymbol: String {
        switch post.bluetoothState {
        case .poweredOn: return "antenna.radiowaves.left.and.right"
        case .unauthorized: return "lock.slash"
        default: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var bluetoothText: String {
        switch post.bluetoothState {
        case .poweredOn: return post.isListening ? "Listening — receive-only" : "Bluetooth ready"
        case .poweredOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission denied (Settings › nightjar)"
        case .unsupported: return "Bluetooth LE unsupported"
        case .resetting: return "Bluetooth resetting…"
        default: return "Waiting for Bluetooth…"
        }
    }

    private func elapsed(since start: TimeInterval) -> String {
        let seconds = Int(max(0, now - start))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}

#if !STORE_BUILD
struct UpdateBanner: View {
    let release: UpdateChecker.Release
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var updater: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Update available — \(release.name)", systemImage: "arrow.down.circle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                Button {
                    updater.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L("Not now"))
            }
            if let install = release.installURL {
                Text("This release carries an over-the-air build. iOS installs it over this one — your logs, notes and settings stay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    openURL(install)
                } label: {
                    Label(L("Update now"),
                          systemImage: "arrow.down.circle.fill")
                        .font(.callout.weight(.semibold))
                }
                .padding(.top, 2)
            } else {
                Text(L("A newer nightjar is out. This release has no over-the-air build, so it installs the Xcode way — open the project and press Run. Your logs are kept."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(destination: release.url) {
                    Label(L("View release"), systemImage: "arrow.up.right.square")
                        .font(.callout)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif

struct DeviceRowView: View {
    let row: DeviceRow
    let now: TimeInterval

    private var quiet: Bool { return row.age(now: now) > 20 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if row.trackerShaped {
                    Image(systemName: "tag.fill").font(.caption).foregroundStyle(.orange)
                }
                if row.flare {
                    Image(systemName: "flame.fill")
                        .font(.caption).foregroundStyle(.yellow)
                        .accessibilityLabel(
                            "Flare: a paired operator is near")
                }
                Spacer()
                Text(row.rssiLast.map { "\($0) dBm" } ?? "? dBm")
                    .font(.callout.monospacedDigit())
                Text(row.trendArrow).font(.callout)
            }
            HStack {
                Text(subtitle)
                    .lineLimit(1)
                Spacer()
                Text(age)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let detail = row.details.first {
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Text(metaLine).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            Text(row.id).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
        }
        .opacity(quiet ? 0.45 : 1)
    }

    private var age: String {
        let seconds = Int(row.age(now: now))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h \(seconds / 60 % 60)m ago"
    }

    /// Kind (when there is a name to headline instead) · the
    /// perimeter band · the rough range, when it can be read.
    private var subtitle: String {
        var parts: [String] = []
        if row.name != nil { parts.append(row.kind) }
        parts.append(row.rangeBand)
        if let d = row.distanceMeters {
            parts.append(d < 10
                ? String(format: "≈%.1f m", d)
                : String(format: "≈%.0f m", d))
        }
        return parts.joined(separator: " · ")
    }

    /// The quiet facts: how often it has spoken, the closest
    /// it ever came, and whether its address rotates.
    private var metaLine: String {
        var parts = ["×\(row.sightings) heard"]
        if let closest = row.rssiClosest {
            parts.append("closest \(closest) dBm")
        }
        if row.rotatingAddress { parts.append("rotating address") }
        return parts.joined(separator: " · ")
    }
}

/// Everything the post knows about one device, on one page —
/// the row is the headline, this is the file. Reads the live
/// row from the post each render, so the numbers keep moving
/// while you watch.
struct DeviceDetailView: View {
    let row: DeviceRow
    @Binding var tab: Int
    @EnvironmentObject private var post: ListeningPost
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @State private var now = Date().timeIntervalSince1970
    @State private var hunting = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var live: DeviceRow {
        post.rows.first { $0.id == row.id } ?? row
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(live.label).font(.title3.weight(.semibold))
                    Text(live.kind).foregroundStyle(.secondary)
                    if live.trackerShaped {
                        Label(L("Tracker-shaped — separated Find My broadcasts"),
                              systemImage: "tag.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if live.rotatingAddress {
                        Label(L("Rotating address — a phone-style private address"),
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section(L("Heard as")) {
                if live.details.isEmpty {
                    Text(L("No decoded details — the broadcast carried nothing the decoders read."))
                        .foregroundStyle(.secondary)
                }
                ForEach(live.details, id: \.self) { detail in
                    Text(detail).font(.callout)
                }
                if !live.makers.isEmpty {
                    LabeledContent(L("Maker"),
                                   value: live.makers.sorted()
                                       .joined(separator: ", "))
                }
            }
            Section(L("Signal")) {
                LabeledContent(L("Last"),
                               value: live.rssiLast.map { "\($0) dBm" } ?? "—")
                LabeledContent(L("Smoothed"),
                               value: live.rssiSmooth.map {
                                   String(format: "%.0f dBm", $0) } ?? "—")
                LabeledContent(L("Closest ever"),
                               value: live.rssiClosest.map { "\($0) dBm" } ?? "—")
                LabeledContent(L("TX power"),
                               value: live.txPowerLast.map { "\($0) dBm" }
                                   ?? L("not advertised"))
                LabeledContent(L("Estimated range"), value: rangeText)
                LabeledContent(L("Trend"), value: live.trend ?? "—")
                Button {
                    hunting = true
                } label: {
                    Label(L("Hunt this signal"),
                          systemImage: "location.viewfinder")
                }
                sparkline
            }
            Section(L("Timing")) {
                LabeledContent(L("First heard"),
                               value: clockTime(live.firstSeen))
                LabeledContent(L("Last heard"),
                               value: clockTime(live.lastSeen))
                LabeledContent(L("Age"), value: ageText)
                LabeledContent(L("Dwell"), value: durationText(live.dwell))
                LabeledContent(L("Sightings"), value: "\(live.sightings)")
                if live.sightingsPerMinute > 0 {
                    LabeledContent(L("Rate"),
                                   value: String(format: "%.1f / min",
                                                 live.sightingsPerMinute))
                }
            }
            if !live.serviceUUIDs.isEmpty {
                Section(L("Services advertised")) {
                    ForEach(live.serviceUUIDs, id: \.self) { uuid in
                        Text(shortUUID(uuid))
                            .font(.caption.monospaced())
                    }
                }
            }
            Section(L("Identifier")) {
                Text(live.id)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text(L("iOS shows a per-host UUID, never the MAC. A rotating-address device returns under a new one when its address rolls."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    if let id = UUID(uuidString: live.id) {
                        let name = live.preferredLabel ?? live.kind
                        mouth.requestWrite(to: id, label: name)
                        Haptics.select()
                        toasts.show(String(format: L("Write target set: %@ — Send tab"), name))
                        tab = 1
                    }
                } label: {
                    Label(L("Write a payload…"), systemImage: "paperplane")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackdrop() }
        .navigationTitle(L("Device"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $hunting) {
            HuntView(targetID: row.id)
                .environmentObject(post)
        }
        .onReceive(clock) { _ in now = Date().timeIntervalSince1970 }
    }

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: L("RSSI history — last %lld sightings"), live.rssiHistory.count))
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(Array(live.rssiHistory.enumerated()),
                        id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 6,
                               height: max(2, CGFloat(value + 100)
                                            / 60 * 32))
                }
            }
            .frame(height: 34, alignment: .bottom)
        }
        .padding(.vertical, 2)
    }

    private var rangeText: String {
        guard let d = live.distanceMeters else { return "—" }
        let text = d < 10
            ? String(format: "≈%.1f m", d)
            : String(format: "≈%.0f m", d)
        return "\(text) (\(live.rangeBand))"
    }

    private var ageText: String {
        let seconds = Int(live.age(now: now))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h \(seconds / 60 % 60)m ago"
    }

    private func clockTime(_ t: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: t))
    }

    private func durationText(_ d: TimeInterval) -> String {
        let s = Int(d)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s / 60 % 60)m"
    }

    /// SIG 128-bit UUIDs spell as their short 0xXXXX form.
    private func shortUUID(_ uuid: String) -> String {
        if uuid.count == 36, uuid.hasPrefix("0000"),
           uuid.hasSuffix(sigBaseSuffix) {
            return "0x" + String(uuid.dropFirst(4).prefix(4))
                .uppercased()
        }
        return uuid
    }
}

// MARK: - Sessions

struct SessionsView: View {
    @EnvironmentObject private var post: ListeningPost
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var mouth: Mouth
    /// Serve's sheet, raised from its new home
    /// under Sessions (Chase's order, 2026-10-22).
    @State private var showServe = false
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @State private var sessions: [SessionSummary] = []
    @State private var selection = Set<String>()
    @State private var showClearConfirm = false
    @State private var shareItem: ShareItem?
    @State private var showNightLog = false

    private var deletable: [SessionSummary] {
        sessions.filter { $0.id != post.session?.id }
    }

    private var totalSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(sessions.reduce(0) { $0 + $1.fileSize }),
            countStyle: .file)
    }

    private var deletableSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(deletable.reduce(0) { $0 + $1.fileSize }),
            countStyle: .file)
    }

    private var selectedDeletableCount: Int {
        deletable.filter { selection.contains($0.id) }.count
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
#if os(iOS)
                Section {
                    Button {
                        showServe = true
                    } label: {
                        HStack {
                            Label(L("Serve — the open door"),
                                  systemImage: "tray.and.arrow.down")
                            Spacer()
                            if mouth.serveRunning {
                                Text(L("Serving"))
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text(L("Serve lives here now — the house's listeners, kept under Sessions."))
                }
#endif
                Section {
                    Button {
                        showNightLog = true
                    } label: {
                        Label(L("Night log — the whole instrument, one timeline"),
                              systemImage: "list.bullet.rectangle")
                    }
                    .foregroundStyle(.primary)
                }
                if sessions.isEmpty {
                    Text(L("No sessions yet. Start one on the Listen tab; each session becomes a .jsonl file you can share to the Mac and feed to `nightjar report` and `nightjar trackers`."))
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    SessionRowView(
                        session: session,
                        isLive: post.session?.id == session.id,
                        onDelete: deleteAction(for: session),
                        onShare: { url in
                            shareItem = ShareItem(items: [url])
                        })
                    .tag(session.id)
                }
                .onDelete { offsets in
                    for index in offsets where post.session?.id != sessions[index].id {
                        SessionStore.delete(sessions[index])
                    }
                    reload()
                }
                if !deletable.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            Haptics.tap()
                            showClearConfirm = true
                        } label: {
                            Label(L("Delete all sessions"),
                                  systemImage: "trash")
                        }
                    } footer: {
                        Text(String(format: L("%lld session(s) · %@ on this phone. Swipe a row, long-press it, or use Edit to pick several. The session recording right now is never deleted."), sessions.count, totalSizeText))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .macColumn(880)
            .macListStyle()
            .background { AppBackdrop() }
            .navigationTitle(L("Sessions"))
            .toolbar {
                ToolbarItem(placement: .houseLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .houseTrailing) {
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                }
#if os(iOS)
                if editMode?.wrappedValue.isEditing == true,
                   selectedDeletableCount > 0 {
                    ToolbarItem(placement: .houseBottom) {
                        Button(String(format: L("Delete selected (%lld)"), selectedDeletableCount),
                               role: .destructive) {
                            deleteSelected()
                        }
                    }
                }
#else
                if selectedDeletableCount > 0 {
                    ToolbarItem(placement: .houseBottom) {
                        Button(String(format: L("Delete selected (%lld)"), selectedDeletableCount),
                               role: .destructive) {
                            deleteSelected()
                        }
                    }
                }
#endif
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
#if os(iOS)
            .sheet(isPresented: $showServe) {
                ServeView()
                    .appThemed(.serve)
            }
#endif
            .confirmationDialog(
                L("Delete all sessions?"),
                isPresented: $showClearConfirm,
                titleVisibility: .visible) {
                Button(String(format: L("Delete %lld sessions (%@)"), deletable.count, deletableSizeText),
                       role: .destructive) {
                    deleteAll()
                }
                Button(L("Cancel"), role: .cancel) { }
            } message: {
                Text(post.session != nil
                     ? L("The session recording right now is kept. This cannot be undone.")
                     : L("Every recorded session file is deleted. This cannot be undone."))
            }
            .onAppear(perform: reload)
            .onChange(of: post.session?.id) { _ in reload() }
            .sheet(isPresented: $showNightLog) {
                NavigationStack {
                    NightLogView()
                        .toolbar {
                            ToolbarItem(
                                placement:
                                    .confirmationAction) {
                                Button(L("Done")) {
                                    showNightLog = false
                                }
                            }
                        }
                }
                .environment(\.backdropSlot, .sessions)
            }
        }
    }

    private func reload() {
        sessions = SessionStore.list()
    }

    /// The row's long-press delete: nothing for the session
    /// still recording, a real closure for everything else.
    /// (A named method, not an inline ternary in the body —
    /// the type checker timed out on that expression.)
    private func deleteAction(for session: SessionSummary)
        -> (() -> Void)?
    {
        if post.session?.id == session.id { return nil }
        return { deleteOne(session) }
    }

    private func deleteOne(_ session: SessionSummary) {
        let removed = SessionStore.delete(session)
        selection.remove(session.id)
        reload()
        if removed {
            toasts.show(L("Session deleted"))
        } else {
            toasts.show(L("Could not delete session"), error: true)
        }
    }

    private func deleteSelected() {
        var gone = 0
        for session in deletable where selection.contains(session.id) {
            SessionStore.delete(session)
            gone += 1
        }
        selection = []
        reload()
        toasts.show(String(format: L("Deleted %lld session(s)"), gone))
    }

    private func deleteAll() {
        let gone = SessionStore.deleteAll(exceptLiveID: post.session?.id)
        selection = []
        reload()
        toasts.show(String(format: L("Deleted %lld session(s)"), gone))
    }
}

struct SessionRowView: View {
    let session: SessionSummary
    let isLive: Bool
    var onDelete: (() -> Void)? = nil
    var onShare: ((URL) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.label ?? "unlabeled")
                        .font(.body.weight(.medium))
                    if isLive {
                        Text(L("recording")).font(.caption).foregroundStyle(.red)
                    } else if session.isUnfinished {
                        Text(L("unfinished")).font(.caption).foregroundStyle(.orange)
                    }
                }
                Text(Self.dateFormatter.string(from: Date(timeIntervalSince1970: session.startedAt)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.url.lastPathComponent)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if !isLive, let onShare {
                Button {
                    onShare(session.url)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            }
        }
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) {
                    Haptics.tap()
                    onDelete()
                } label: {
                    Label(L("Delete session"), systemImage: "trash")
                }
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let duration = session.duration {
            let minutes = Int(duration / 60)
            parts.append(minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
        }
        if let count = session.sightings {
            parts.append("\(count) sightings")
        }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(session.fileSize),
                                               countStyle: .file))
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - About

struct AboutView: View {
#if !STORE_BUILD
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var updater: UpdateChecker
    @State private var showSupport = false
#endif
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var emcon: Emcon
    @EnvironmentObject private var toasts: ToastCenter
    @ObservedObject private var languageCenter =
        LanguageCenter.shared
    @State private var showLanguageSheet = false
    // The developer switch deliberately lives
    // outside the settings registry, like the
    // language-welcome marker: wiping preferences
    // must not disarm the crash recorder.
    @State private var developerOn =
        UserDefaults.standard.bool(
            forKey: DevKit.enabledKey)
    @State private var showDeveloperSheet = false
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("listen.bthomeV1") private var bthomeV1 = false
    @AppStorage("postName") private var postName = "phone"
    @State private var confirmReset = false
    @State private var showColours = false
    @State private var setupShare: ShareItem?
    @State private var importingSetup = false
    @State private var sourceVerdict: String?
    @State private var checkingSource = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Image("NightwareBanner")
                        .resizable()
                        .scaledToFit()
                        .listRowInsets(EdgeInsets())
                }
                // The development wire (Chase's ask,
                // 2026-10-22): where the lab posts as
                // it builds — releases, field notes,
                // what's next.
                Section {
                    Link(destination: URL(string: "https://x.com/nightwarelabz")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "at.sign")
                                .font(.title3)
                                .foregroundStyle(.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Follow the development"))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(L("@nightwarelabz on X — releases, field notes, and what the lab is building next."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(header: Text(L("Version"))) {
                    Text(String(format: L("nightjar for iOS %@ · log format 1"), AppInfo.version))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://github.com/nightwarelabz/nightjar/blob/main/PRIVACY.md")!) {
                        Label(L("Privacy Policy"), systemImage: "hand.raised")
                    }
#if !STORE_BUILD
                    if let short = SourceStamp.shortCommit {
                        Text(L("Source — built from ")
                             + short
                             + (SourceStamp.uncommittedChanges > 0
                                ? String(format: L(" · %lld uncommitted change(s) rode along"), SourceStamp.uncommittedChanges)
                                : L(" · the tree was clean")))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L("Source — no stamp in this build"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Haptics.tap()
                        checkingSource = true
                        Task {
                            let head = await SourceStamp
                                .currentRemoteHead()
                            checkingSource = false
                            sourceVerdict = head.map {
                                SourceStamp.verdict(
                                    remoteHead: $0)
                            } ?? L("GitHub would not answer — the check needs the network.")
                        }
                    } label: {
                        HStack {
                            Text(L("Verify against the current source"))
                            Spacer()
                            if checkingSource {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(checkingSource)
                    if let sourceVerdict {
                        Text(sourceVerdict)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
#endif
#if !STORE_BUILD
                    if let release = updater.available {
                        if let install = release.installURL {
                            Button {
                                Haptics.tap()
                                openURL(install)
                            } label: {
                                Label(String(format: L("Update to %@ — install now"), release.name),
                                      systemImage: "arrow.down.circle.fill")
                            }
                        } else {
                            Link(destination: release.url) {
                                Label("Update available — \(release.name)",
                                      systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                    Button {
                        Haptics.tap()
                        Task { await updater.check() }
                    } label: {
                        HStack {
                            Text(L("Check for updates"))
                            Spacer()
                            if updater.checking {
                                ProgressView()
                            } else if updater.noReleasesYet {
                                Text(L("no releases published yet"))
                                    .foregroundStyle(.secondary)
                            } else if updater.available == nil, updater.lastChecked != nil {
                                Text(L("up to date")).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(updater.checking)
#endif
                }
                Section(header: Text(L("Language"))) {
                    Button {
                        Haptics.tap()
                        showLanguageSheet = true
                    } label: {
                        HStack {
                            Label(L("App language"),
                                  systemImage: "globe")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(languageCenter
                                .effectiveNativeName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    ExplainToggle(
                        text: L("The whole house in your language — every tab, setting and switch, and Skelli herself — the moment you choose it, with no relaunch. The room behind this door lists every tongue by its own name, shows the one in force, and turns the house for the languages that read right to left."))
                }
                Section(header: Text("Developer")) {
                    Toggle("Developer options",
                           isOn: $developerOn)
                        .onChange(of: developerOn) { on in
                            Haptics.select()
                            UserDefaults.standard.set(
                                on,
                                forKey: DevKit.enabledKey)
                            if on {
                                CrashRecorder.install()
                                DevLog.event(
                                    "developer",
                                    "developer options "
                                        + "turned on")
                            } else {
                                CrashRecorder
                                    .setArmed(false)
                            }
                        }
                    if developerOn {
                        Button {
                            Haptics.tap()
                            showDeveloperSheet = true
                        } label: {
                            HStack {
                                Label("Developer console",
                                      systemImage: "wrench.and.screwdriver")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    ExplainToggle(
                        text: "For building and improving the house. While this is on, the app keeps a flight recorder of what Skelli and the system were just doing, and if the app ever crashes it writes down why — the signal or exception and the backtrace — before it dies. The console reads it all back and hands it over as one log file, ready to copy or share. Off, nothing is recorded.")
                }
                Section(header: Text(L("Your setup"))) {
                    ExplainToggle(
                        title: L("How your setup is kept"),
                        text: L("Your configuration — every toggle, picker and preference in the house — is mirrored into the Keychain as it changes. The Keychain outlives the app: the seven-day expiry, a deletion, a reinstall — a fresh install on this device restores your setup before anything reads a setting. Ordinary updates and re-signs keep it anyway: the data container belongs to the bundle, not the signature. Export writes it to one file for a new device; import reads that file back. Payloads, macros and logs are data, not settings, and keep their own exports."))
                    Button {
                        Haptics.tap()
                        if let data = HouseSetup.exportData() {
                            let url = FileManager.default
                                .temporaryDirectory
                                .appendingPathComponent(
                                    "nightjar-setup.json")
                            if (try? data.write(
                                    to: url)) != nil {
                                setupShare = ShareItem(
                                    items: [url])
                            } else {
                                toasts.show(L("The setup file would not write"))
                            }
                        }
                    } label: {
                        Label(L("Export setup"),
                              systemImage: "square.and.arrow.up")
                    }
                    Button {
                        Haptics.tap()
                        importingSetup = true
                    } label: {
                        Label(L("Import setup"),
                              systemImage: "square.and.arrow.down")
                    }
                }
                Section(header: Text(L("Appearance"))) {
                    Button {
                        Haptics.tap()
                        showColours = true
                    } label: {
                        HStack {
                            Label(L("Themes & backdrops"),
                                  systemImage: "paintpalette")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    ExplainToggle(
                        text: L("Six themes ship with the app and you can tailor your own; every tab may wear its own backdrop — the living wallpaper, the Jolly Roger, the plain theme colour, or your own image or GIF."))
                    if let reel = Wallpaper.image {
                        Text(String(format: L("Living wallpaper: playing (%lld×%lld pt) — it loops behind every tab, beginning to end, forever."), Int(reel.size.width), Int(reel.size.height)))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if UIImage(named: "AppBackground") != nil {
                        Text(L("The living wallpaper has not landed in this build — the retired Jolly Roger stands in behind every tab until wallpaper.png joins the bundle."))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(L("No backdrop in this build. The app looks for wallpaper.png in the bundle (or a \"Wallpaper\" data asset) — and wears plain black until it finds one."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section(header: Text(L("This post"))) {
                    HStack {
                        Text(L("Post name"))
                        Spacer()
                        TextField(L("phone"), text: $postName)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .foregroundStyle(.secondary)
                    }
                    ExplainToggle(
                        text: L("The name of this ear, written into every session. The Mac's fusion uses it to tell your phone apart from your other posts — give each one its own name."))
                }
                Section(header: Text(L("Listening"))) {
                    Toggle(L("Keep the screen awake while listening"), isOn: $keepScreenAwake)
                        .onChange(of: keepScreenAwake) { _ in
                            Haptics.select()
                        }
                    Toggle(L("Decode BTHome v1 sensors"), isOn: $bthomeV1)
                        .onChange(of: bthomeV1) { _ in
                            Haptics.select()
                        }
                    ExplainToggle(
                        text: L("BTHome v1 is the legacy generation of the BTHome sensor format. Its encryption carries no replay protection — a captured v1 advertisement can be replayed verbatim and accepted — so the house decodes v1 only when you switch it on here, and only ever reads it: nothing in the app acts on a v1 reading. BTHome v2 is unaffected and always decoded."))
                    ExplainToggle(
                        text: L("Foreground sessions hear everything. In the background iOS only delivers advertisements from a fixed list of services, so a backgrounded session keeps hearing tracker tags (Tile, SmartThings, Find My Device network, Fast Pair) but not phones, AirTags or anything else that broadcasts only manufacturer data."))
                }
                Section(header: Text(L("The app"))) {
                    ExplainToggle(
                        title: L("What this app is"),
                        text: L("This is nightjar: the listening post from nightjar, plus a mouth. The Listen tab is the purist half — it scans and logs advertisements and never connects, pairs or sends, exactly like the upstream app. The Send and Serve tabs are the hack half: they transmit, but only when you press their buttons, to targets you type. The two halves share no radio state; the ear stays pure, the mouth is a ")
                            + "different organ.\n\nSend and "
                            + L("Serve work while the app is on screen. iOS does not let a sideloaded app hold listeners or advertisements open in the background, so a beacon or server stops being reachable when you leave the app — the Listen tab keeps its background hearing, the mouth does not."))
                    Text(L("nightjar is a testing instrument for devices and networks you own, or that you are engaged in writing to test. Aim everything it sends, scans, plants, or records only at targets you are authorized for. You are responsible for your authorization; the author is not responsible for misuse against devices or networks you were not authorized to test."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
#if !STORE_BUILD
                Section(header: Text(L("Support the work"))) {
                    Button {
                        Haptics.tap()
                        showSupport = true
                    } label: {
                        HStack {
                            Label {
                                Text(L("Buy me a coffee"))
                            } icon: {
                                Image(systemName: "cup.and.saucer.fill")
                                    .foregroundStyle(Color(red: 0.85, green: 0.58, blue: 0.30))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(L("Free and open source, always. If you'd like to help cover the costs, there's a quiet door here — no pressure at all."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
#endif
                Section(header: Text(L("Defaults")),
                        footer: Text(L("The reset is a factory reset: it erases everything — data included — and returns the app to exactly as it shipped."))) {
                    ExplainToggle(
                        title: L("What a reset does"),
                        text: L("Every setting in this app has a sane default — the safe, legible choice — and the app runs on those defaults until you configure otherwise. The reset below is a factory reset: it erases everything the house has gathered and returns the app to exactly as it shipped."))
                    Button(role: .destructive) {
                        Haptics.warn()
                        confirmReset = true
                    } label: {
                        Text(L("Factory reset — erase everything"))
                    }
                }
                Section(header: Text(L("Session logs"))) {
                    ExplainToggle(
                        title: L("Getting logs to the Mac"),
                        text: L("Each session is a JSON Lines file in Files › On My iPhone › nightjar › sessions, and shareable from the Sessions tab. On the Mac: nightjar report <file> and nightjar trackers <file>."))
                }
            }
            .scrollContentBackground(.hidden)
            .macColumn(880)
            .macListStyle()
            .background { AppBackdrop() }
            .navigationTitle(L("About"))
            .sheet(isPresented: $showColours) {
                NavigationStack {
                    ColoursView()
                        .toolbar {
                            ToolbarItem(
                                placement: .confirmationAction) {
                                Button(L("Done")) {
                                    Haptics.tap()
                                    showColours = false
                                }
                            }
                        }
                }
            }
            .sheet(item: $setupShare) { item in
                ShareSheet(items: item.items)
            }
            .sheet(isPresented: $showLanguageSheet) {
                LanguageSheet()
            }
            .sheet(isPresented: $showDeveloperSheet) {
                DeveloperSheet()
            }
            .fileImporter(isPresented: $importingSetup,
                          allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result,
                      url.startAccessingSecurityScopedResource(),
                      let data = try? Data(contentsOf: url)
                else {
                    toasts.show(L("That setup file would not come"))
                    return
                }
                url.stopAccessingSecurityScopedResource()
                if HouseSetup.importData(data) {
                    toasts.show(L("Setup restored — relaunch to see it everywhere"))
                } else {
                    toasts.show(L("That is not a nightjar setup file"))
                }
            }
#if !STORE_BUILD
            .sheet(isPresented: $showSupport) {
                NavigationStack {
                    SupportView()
                        .toolbar {
                            ToolbarItem(
                                placement: .confirmationAction) {
                                Button(L("Done")) {
                                    Haptics.tap()
                                    showSupport = false
                                }
                            }
                        }
                }
            }
#endif
            .confirmationDialog(L("Factory reset?"),
                                isPresented: $confirmReset) {
                Button(L("Erase everything"), role: .destructive) {
                    Haptics.error()
                    SaneDefaults.reset(mouth: mouth,
                                       emcon: emcon)
                    toasts.show(L("Factory reset — as shipped. Close and reopen nightjar for the fresh house."))
                }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(L("Everything returns to exactly as it shipped: settings, theme and backdrops, EMCON's condition, the app lock and every seal, Skelli's memory, sessions, logs, saved files, and the keychain. Anything transmitting stands down first. This cannot be undone."))
            }
        }
    }
}

#if !STORE_BUILD
// MARK: - Support

/// The quiet door. A warm little room of its own — coffee colours,
/// apart from every theme in the house — that asks for nothing and
/// means it: the app is free either way, and this screen exists only
/// so an operator who wants to chip in can find the way. It links
/// out to Buy Me a Coffee; the app itself never touches a payment.
struct SupportView: View {
    private let cream = Color(red: 0.96, green: 0.91, blue: 0.83)
    private let tan = Color(red: 0.76, green: 0.65, blue: 0.52)
    private let amber = Color(red: 0.85, green: 0.58, blue: 0.30)
    private let espresso = Color(red: 0.10, green: 0.06, blue: 0.03)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.10, blue: 0.06),
                         Color(red: 0.05, green: 0.03, blue: 0.02)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(amber.opacity(0.16))
                            .frame(width: 118, height: 118)
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(amber)
                    }
                    .padding(.top, 36)

                    Text(L("Support the work"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(cream)

                    VStack(spacing: 14) {
                        Text(L("nightjar is free, and it stays free either way — every tool in it is already yours. There are no paywalls here, and there never will be."))
                        Text(L("If it has earned its keep on your phone and you'd like to chip in, a coffee helps cover the developer fee and the test gear it takes to build this. And if not — that's cool too. Truly."))
                        Text(L("— Chase"))
                            .foregroundStyle(amber)
                    }
                    .font(.body)
                    .foregroundStyle(tan)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)

                    Link(destination: URL(string: "https://buymeacoffee.com/realTechnique")!) {
                        HStack(spacing: 10) {
                            Image(systemName: "cup.and.saucer.fill")
                            Text(L("Buy me a coffee"))
                        }
                        .font(.headline)
                        .foregroundStyle(espresso)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(amber, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 6)

                    Text(L("Opens Buy Me a Coffee in your browser — the app never sees or touches your payment details."))
                        .font(.footnote)
                        .foregroundStyle(tan.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle(L("Support"))
        .navigationBarTitleDisplayMode(.inline)
        .houseToolbarColorScheme()
    }
}
#endif

#Preview {
    ContentView()
        .environmentObject(ListeningPost())
#if !STORE_BUILD
        .environmentObject(UpdateChecker())
#endif
        .environmentObject(Mouth())
        .environmentObject(ToastCenter())
}
