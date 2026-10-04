// The 6-digit code an approved Mac sign-in needs, shown until Done or its expiry, with a warning
// never to pass it on (device-code phishing).
// Exports: MacSigninCodeView. The code lives only in memory; nothing here copies or stores it.
// Dependencies: SwiftUI, HibossKit PairingValidity, MacSigninCode, Theme tokens.

import HibossKit
import SwiftUI

struct MacSigninCodeView: View {
    let code: MacSigninCode
    let onDone: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                if code.isExpired(at: context.date) {
                    expired
                } else {
                    live(now: context.date)
                }
                Spacer(minLength: 0)
                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity, minHeight: 44)
                }
                .prominentAction()
                .accessibilityIdentifier("mac-signin.done")
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper.ignoresSafeArea())
        }
    }

    private func live(now: Date) -> some View {
        VStack(spacing: 14) {
            Text("Type this code on your Mac")
                .font(.hbH2)
                .multilineTextAlignment(.center)
            // The label is whatever the requesting Mac chose, so it is quoted, never vouched for.
            Text("A Mac calling itself “\(code.deviceLabel)”")
                .font(.hbBody)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            Text(verbatim: Self.grouped(code.code))
                .font(.hbCode)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(Text("Sign-in code \(Self.spokenDigits(code.code))"))
                .accessibilityIdentifier("mac-signin.code")
            if let expiresAt = code.expiresAt {
                Text("Expires in \(PairingValidity.formatted(remainingSeconds: PairingValidity.remainingSeconds(expiresAt: expiresAt, now: now)))")
                    .font(.hbCallout)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
            }
            phishingWarning
        }
        .frame(maxWidth: .infinity)
    }

    /// Someone who shows the boss their own QR code still needs this code; asking for it is the attack.
    private var phishingWarning: some View {
        Label {
            Text("Only type this code on a Mac that is in front of you. Never read it out or send it to anyone, even if they ask for it.")
        } icon: {
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Theme.warn)
        }
        .font(.hbCallout)
        .foregroundStyle(Theme.ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mac-signin.warning")
    }

    private var expired: some View {
        ContentUnavailableView {
            Label("Code expired", systemImage: "clock.badge.exclamationmark")
        } description: {
            Text("Start again on the Mac to get a new code.")
        }
        .accessibilityIdentifier("mac-signin.expired")
    }

    /// "123 456": two groups of three are easier to read across a desk than six in a row.
    static func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    /// "1 2 3 4 5 6", so VoiceOver reads each digit instead of a six-digit number.
    static func spokenDigits(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }
}
