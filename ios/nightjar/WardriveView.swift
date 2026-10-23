import SwiftUI

// MARK: - WardriveView
//
// The War Driving room: raised as a sheet
// from the Listen tab (the tabs never push).
// The drive's state is the center's, so the
// room can be dismissed mid-drive and the
// survey rolls on; the counters read live
// from WardriveCenter, the finished drives
// wait below with their weights — each one
// a file the operator can hand over through
// Deliveries or throw away. The boundary
// card says, in the room itself, exactly
// what iOS lets an app see of the Wi-Fi
// world: the connected network, and no more.

struct WardriveView: View {
    @ObservedObject private var drive =
        WardriveCenter.shared
    @EnvironmentObject private var post: ListeningPost
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [WardriveSession] = []
    @State private var refusal: String?
    @State private var filedNote: String?

    var body: some View {
        NavigationStack {
            List {
                driveSection
                boundarySection
                sessionsSection
            }
            .scrollContentBackground(.hidden)
            .macColumn(880)
            .macListStyle()
            .background { AppBackdrop() }
            .navigationTitle(L("War Driving"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .onAppear {
                WardriveCenter.shared.post = post
                sessions = WardriveCenter.sessions()
            }
            .onChange(of: drive.running) {
                sessions = WardriveCenter.sessions()
            }
        }
    }

    // MARK: The drive itself

    @ViewBuilder private var driveSection: some View {
        Section {
            if drive.running {
                LabeledContent(L("Status"),
                               value: L("rolling"))
                LabeledContent(L("Devices heard"),
                               value: "\(drive.uniqueDevices)")
                LabeledContent(L("Networks joined"),
                               value: "\(drive.uniqueNetworks)")
                LabeledContent(
                    L("Distance"),
                    value: WardriveCenter.distanceText(
                        drive.distanceMetersTotal))
                LabeledContent(L("Records"),
                               value: "\(drive.recordCount)")
                if let name = drive.currentLogName {
                    Text(name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    drive.stop()
                } label: {
                    Label(L("Stop the drive"),
                          systemImage: "stop.circle.fill")
                }
            } else {
                Button {
                    refusal = drive.start()
                    sessions = WardriveCenter.sessions()
                } label: {
                    Label(L("Start the drive"),
                          systemImage: "play.circle.fill")
                }
                if let refusal {
                    Text(refusal)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Text(L("The post listens while you move; every few seconds the drive writes what it heard, where you were, and the network you are joined to."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: The boundary, in the room

    private var boundarySection: some View {
        Section {
            Text(L("iOS shows an app only the Wi-Fi network you are connected to — a drive logs each network as you join it, and every Bluetooth device the post hears."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: The shelf of drives

    private var sessionsSection: some View {
        Section(header: Text(L("Drives on file"))) {
            if let filedNote {
                Text(filedNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if sessions.isEmpty {
                Text(L("No drives yet."))
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(.callout.monospaced())
                        Text(String(
                            format: L("%lld records · %@"),
                            Int64(session.count),
                            Self.byteText(session.bytes)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        export(session)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(drive.running
                        && drive.currentLogName == session.name)
                    Button(role: .destructive) {
                        WardriveCenter.deleteSession(session.name)
                        sessions = WardriveCenter.sessions()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(drive.running
                        && drive.currentLogName == session.name)
                }
            }
        }
    }

    /// File a drive's log onto her shelf —
    /// the copy the share sheet takes away.
    private func export(_ session: WardriveSession) {
        let url = WardriveCenter.documentsDirectory
            .appendingPathComponent(session.name)
        if DeliveriesCenter.shared.addFile(
            at: url, displayName: session.name) != nil {
            filedNote = String(
                format: L("%@ is filed in Deliveries."),
                session.name)
        }
    }

    static func byteText(_ bytes: Int) -> String {
        if bytes < 1024 {
            return String(format: L("%lld B"),
                          Int64(bytes))
        }
        if bytes < 1_048_576 {
            return String(format: L("%.1f KB"),
                          Double(bytes) / 1024)
        }
        return String(format: L("%.1f MB"),
                      Double(bytes) / 1_048_576)
    }
}
