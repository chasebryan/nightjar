import SwiftUI

// MARK: - AppLockView
//
// The app lock's settings room, raised as a
// sheet from the Vault — the lock is the
// Vault's own concern, and this is the only
// place it is ever managed. Arming asks for
// a passcode and the operator's own choices
// (cipher, stretching, re-lock grace,
// biometrics); changing the passcode, the
// scheme or removing the lock all ask for
// the current passcode first. The console
// and Skelli can only ever REPORT the lock —
// no other surface can move it.

struct AppLockSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var armed =
        AppLockStandard.isArmed()
    @State private var suite: AppLockSuite =
        AppLockStandard.suite()
    @State private var rounds =
        AppLockStandard.kdfRounds()
    @State private var grace =
        AppLockStandard.graceSeconds()
    @State private var biometrics =
        AppLockStandard.biometricsEnabled()
    @State private var showSetup = false
    @State private var showScheme = false
    @State private var showChange = false
    @State private var showRemove = false

    var body: some View {
        NavigationStack {
            List {
                if armed {
                    statusSection
                    tuningSection
                    schemeSection
                    passcodeSection
                } else {
                    setupSection
                }
            }
            .navigationTitle(L("App lock"))
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showSetup) {
                AppLockSetupView { refresh() }
            }
            .sheet(isPresented: $showScheme) {
                AppLockSchemeView(
                    suite: suite, rounds: rounds) {
                    refresh()
                }
            }
            .sheet(isPresented: $showChange) {
                AppLockChangeView { refresh() }
            }
            .sheet(isPresented: $showRemove) {
                AppLockRemoveView { refresh() }
            }
        }
    }

    private func refresh() {
        armed = AppLockStandard.isArmed()
        suite = AppLockStandard.suite()
        rounds = AppLockStandard.kdfRounds()
        grace = AppLockStandard.graceSeconds()
        biometrics = AppLockStandard.biometricsEnabled()
        AppLockCenter.shared.syncWithStandard()
    }

    // MARK: - Disarmed

    private var setupSection: some View {
        Section(header: Text(L("The gate"))) {
            Text(L("No passcode stands on this app. Set one, and nightjar opens onto a lock — sealed under the cipher and the stretching you choose."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                showSetup = true
            } label: {
                Label(L("Set a passcode"),
                      systemImage: "lock")
            }
        }
    }

    // MARK: - Armed

    private var statusSection: some View {
        Section(header: Text(L("Status"))) {
            Label(L("the app lock is on"),
                  systemImage: "lock.fill")
            HStack {
                Text(L("Cipher"))
                Spacer()
                Text(suite.label)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(L("Key stretching"))
                Spacer()
                Text(String(format: L("%lld rounds"),
                            Int64(rounds)))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The two choices that carry no seal of
    /// their own — when the gate falls again,
    /// and whether a face may open it — move
    /// freely, no passcode asked.
    private var tuningSection: some View {
        Section(header: Text(L("Coming and going"))) {
            AppLockGracePicker(selection: $grace)
                .onChange(of: grace) { _, value in
                    AppLockStandard.setGraceSeconds(
                        value)
                }
            if AppLockStandard.biometricsAvailable() {
                Toggle(L("allow biometrics"),
                       isOn: $biometrics)
                    .onChange(of: biometrics) { _, value in
                        AppLockStandard
                            .setBiometricsEnabled(value)
                    }
            }
        }
    }

    private var schemeSection: some View {
        Section(
            header: Text(L("Protection")),
            footer: Text(L("A new cipher or new stretching reseals the gate under the same passcode — the passcode is asked again, and never changes hands."))) {
            Button {
                showScheme = true
            } label: {
                Label(L("Change cipher or stretching"),
                      systemImage: "lock.rotation")
            }
        }
    }

    private var passcodeSection: some View {
        Section {
            Button {
                showChange = true
            } label: {
                Label(L("Change passcode"),
                      systemImage: "key")
            }
            Button(role: .destructive) {
                showRemove = true
            } label: {
                Label(L("Remove the lock"),
                      systemImage: "lock.open")
            }
        }
    }
}

// MARK: - The shared pickers

private struct AppLockSuitePicker: View {
    @Binding var selection: AppLockSuite

    var body: some View {
        Picker(L("Cipher"), selection: $selection) {
            ForEach(AppLockSuite.allCases,
                    id: \.self) { suite in
                Text(suite.label).tag(suite)
            }
        }
    }
}

private struct AppLockRoundsPicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker(L("Key stretching"),
               selection: $selection) {
            Text(L("standard — 100,000 rounds"))
                .tag(100_000)
            Text(L("high — 300,000 rounds"))
                .tag(300_000)
            Text(L("maximum — 600,000 rounds"))
                .tag(600_000)
        }
    }
}

private struct AppLockGracePicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker(L("Re-lock"), selection: $selection) {
            Text(L("lock immediately")).tag(0)
            Text(L("after 1 minute")).tag(60)
            Text(L("after 5 minutes")).tag(300)
        }
    }
}

// MARK: - Setting the passcode

private struct AppLockSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var confirm = ""
    @State private var suite: AppLockSuite =
        AppLockStandard.suite()
    @State private var rounds =
        AppLockStandard.kdfRounds()
    @State private var grace = 0
    @State private var biometrics = false
    @State private var notice: String?

    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L("Passcode"))) {
                    SecureField(L("passcode"),
                                text: $entry)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField(L("confirm the passcode"),
                                text: $confirm)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                Section(header: Text(L("Protection"))) {
                    AppLockSuitePicker(
                        selection: $suite)
                    AppLockRoundsPicker(
                        selection: $rounds)
                }
                Section(header: Text(L("Coming and going"))) {
                    AppLockGracePicker(
                        selection: $grace)
                    if AppLockStandard
                        .biometricsAvailable() {
                        Toggle(L("allow biometrics"),
                               isOn: $biometrics)
                    }
                }
                Section {
                    Button {
                        save()
                    } label: {
                        Label(L("Set the lock"),
                              systemImage: "lock.fill")
                    }
                }
                if let notice {
                    Section {
                        Text(notice)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L("Set a passcode"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard !entry.isEmpty else {
            notice = L("enter a passcode first")
            return
        }
        guard entry == confirm else {
            notice = L("the passcodes do not match")
            return
        }
        do {
            try AppLockStandard.configure(
                passcode: entry, suite: suite,
                rounds: rounds)
            AppLockStandard.setGraceSeconds(grace)
            AppLockStandard.setBiometricsEnabled(
                biometrics)
            onDone()
            dismiss()
        } catch {
            notice = L("the lock could not be set")
        }
    }
}

// MARK: - Changing the scheme

private struct AppLockSchemeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var newSuite: AppLockSuite
    @State private var newRounds: Int
    @State private var notice: String?

    let onDone: () -> Void

    init(suite: AppLockSuite, rounds: Int,
         onDone: @escaping () -> Void) {
        _newSuite = State(initialValue: suite)
        _newRounds = State(initialValue: rounds)
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L("Protection"))) {
                    AppLockSuitePicker(
                        selection: $newSuite)
                    AppLockRoundsPicker(
                        selection: $newRounds)
                }
                Section(header: Text(L("Passcode"))) {
                    SecureField(L("passcode"),
                                text: $entry)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                Section {
                    Button {
                        apply()
                    } label: {
                        Label(L("Reseal the gate"),
                              systemImage: "lock.rotation")
                    }
                }
                if let notice {
                    Section {
                        Text(notice)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L("Change protection"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
    }

    private func apply() {
        if AppLockStandard.reconfigure(
            passcode: entry, suite: newSuite,
            rounds: newRounds) {
            onDone()
            dismiss()
        } else {
            notice = L("wrong passcode")
            entry = ""
        }
    }
}

// MARK: - Changing the passcode

private struct AppLockChangeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var oldEntry = ""
    @State private var newEntry = ""
    @State private var confirm = ""
    @State private var notice: String?

    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L("Current passcode"))) {
                    SecureField(L("passcode"),
                                text: $oldEntry)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                Section(header: Text(L("New passcode"))) {
                    SecureField(L("new passcode"),
                                text: $newEntry)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField(L("confirm the passcode"),
                                text: $confirm)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                Section {
                    Button {
                        save()
                    } label: {
                        Label(L("Change passcode"),
                              systemImage: "key")
                    }
                }
                if let notice {
                    Section {
                        Text(notice)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L("Change passcode"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard !newEntry.isEmpty else {
            notice = L("enter a passcode first")
            return
        }
        guard newEntry == confirm else {
            notice = L("the passcodes do not match")
            return
        }
        if AppLockStandard.changePasscode(
            old: oldEntry, new: newEntry) {
            onDone()
            dismiss()
        } else {
            notice = L("wrong passcode")
            oldEntry = ""
        }
    }
}

// MARK: - Removing the lock

private struct AppLockRemoveView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var notice: String?

    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L("Passcode"))) {
                    SecureField(L("passcode"),
                                text: $entry)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                Section {
                    Button(role: .destructive) {
                        remove()
                    } label: {
                        Label(L("Remove the lock"),
                              systemImage: "lock.open")
                    }
                }
                if let notice {
                    Section {
                        Text(notice)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L("Remove the lock"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
    }

    private func remove() {
        if AppLockStandard.disarm(passcode: entry) {
            onDone()
            dismiss()
        } else {
            notice = L("wrong passcode")
            entry = ""
        }
    }
}
