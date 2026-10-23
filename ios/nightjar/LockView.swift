import LocalAuthentication
import SwiftUI

// MARK: - LockView
//
// The gate itself: the whole of the app
// when the app lock stands. The banner, the
// word, one field, one button — and, when
// the operator has allowed it, the biometric
// door beside the passcode door. There is
// deliberately NO way out of this view: no
// dismiss, no tab, no sheet. The passcode
// opens it, or biometrics the operator
// enabled opens it, and nothing else does.
//
// Wrong guesses are priced by the standard
// (AppLockStandard): counted, and after
// five the gate itself refuses for a
// doubling wait. The field clears on every
// failure; nothing about a wrong guess is
// ever echoed back.

struct LockView: View {
    @State private var entry = ""
    @State private var notice: String?
    @State private var lockoutLeft = 0
    @State private var biometricsTried = false

    private var biometricsOffered: Bool {
        AppLockStandard.biometricsEnabled()
            && AppLockStandard.biometricsAvailable()
    }

    private var biometricsLabel: String {
        AppLockStandard.biometryKind() == .touchID
            ? L("use Touch ID") : L("use Face ID")
    }

    private var biometricsSymbol: String {
        AppLockStandard.biometryKind() == .touchID
            ? "touchid" : "faceid"
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VStack(spacing: 22) {
                Image("NightwareBanner")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420)
                Text(L("nightjar is locked"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                SecureField(L("passcode"), text: $entry)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.go)
                    .onSubmit { attempt() }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                    .frame(maxWidth: 320)
                Button {
                    attempt()
                } label: {
                    Text(L("Unlock"))
                        .frame(maxWidth: 320)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                if biometricsOffered {
                    Button {
                        attemptBiometrics()
                    } label: {
                        Label(biometricsLabel,
                              systemImage: biometricsSymbol)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white)
                }
                if lockoutLeft > 0 {
                    Text(String(format: L(
                        "too many attempts — try "
                        + "again in %lld seconds"),
                        Int64(lockoutLeft)))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(28)
            .frame(maxWidth: 480)
        }
        .onAppear {
            refreshLockout()
            if biometricsOffered && !biometricsTried {
                biometricsTried = true
                attemptBiometrics()
            }
        }
    }

    private func refreshLockout() {
        lockoutLeft = Int(ceil(
            AppLockStandard.lockoutRemaining()))
    }

    private func attempt() {
        refreshLockout()
        guard lockoutLeft <= 0 else {
            notice = L("too many attempts — try again shortly")
            return
        }
        guard !entry.isEmpty else { return }
        if AppLockStandard.verify(entry) {
            AppLockStandard.recordSuccess()
            entry = ""
            notice = nil
            AppLockCenter.shared.unlock()
        } else {
            AppLockStandard.recordFailure()
            entry = ""
            notice = L("wrong passcode")
            refreshLockout()
        }
    }

    private func attemptBiometrics() {
        let context = LAContext()
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: L("unlock nightjar")
        ) { success, _ in
            guard success else { return }
            DispatchQueue.main.async {
                AppLockStandard.recordSuccess()
                AppLockCenter.shared.unlock()
            }
        }
    }
}
