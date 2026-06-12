// Geführte Ersteinrichtung im „Kino-Modus" (inspiriert von Arcs Onboarding):
// paged Flow über 5 Schritte auf einem langsam wabernden Indigo-Gradient —
// Hello -> CLI-Check (gestaffelte Häkchen) -> erster Account -> Aha-Moment
// (Live-Usage zählt hoch) -> Berechtigungen (Priming NACH dem Aha) -> Finale.
//
// AppKit-Host statt SwiftUI-Window-Scene: aus einer LSUIElement-Menüleisten-App lässt
// sich ein NSWindow direkt und zuverlässig zeigen (kein Scene-/Fokus-Gefrickel).
// Öffnet sich automatisch beim ersten Start ohne Accounts; manuell über Einstellungen.

import AppKit
import CleverSwitchKit
import SwiftUI

@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: OnboardingView(model: model, close: { hide() }))
        let w = NSWindow(contentViewController: hosting)
        w.title = L10n.t("onboarding_title")
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func hide() {
        window?.orderOut(nil)
    }
}

// MARK: - Schritte

private enum OnboardingStep: Int, CaseIterable {
    case hello, cli, account, aha, permissions, finale
}

private struct OnboardingView: View {
    let model: AppModel
    let close: () -> Void

    @State private var step: OnboardingStep = .hello
    @State private var helloAppeared = false  // Entrance-Animation des Hello-Schritts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var totalAccounts: Int {
        model.providers.reduce(0) { $0 + model.accounts(for: $1).count }
    }

    var body: some View {
        ZStack {
            AnimatedGradient(paused: reduceMotion)
            VStack(spacing: 0) {
                Spacer(minLength: 28)
                stepContent
                    .id(step)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity))
                    )
                Spacer(minLength: 12)
                footer
            }
            .padding(28)
        }
        .frame(width: 640, height: 480)
        .preferredColorScheme(.dark)
        // Aha-Moment automatisch betreten, sobald der erste Login durch ist —
        // Verhaltens-Trigger statt „Weiter"-Klick.
        .onChange(of: totalAccounts) { oldCount, newCount in
            if newCount > oldCount, step == .account { advance(.aha) }
        }
    }

    private func advance(_ to: OnboardingStep) {
        if reduceMotion {
            step = to
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = to }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .hello: helloStep
        case .cli: cliStep
        case .account: accountStep
        case .aha: ahaStep
        case .permissions: permissionsStep
        case .finale: finaleStep
        }
    }

    // MARK: Schritt 0 — Hello (Kino-Moment)

    private var helloStep: some View {
        // Gestaffelter Einzug (Icon schwebt mit Spring ein, Texte und Button folgen) —
        // der „Filmvorspann"-Moment beim allerersten Öffnen.
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 108, height: 108)
                .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                .scaleEffect(helloAppeared ? 1 : 0.4)
                .opacity(helloAppeared ? 1 : 0)
                .animation(entrance(delay: 0.1), value: helloAppeared)
            Text(L10n.t("onboarding_hello_title"))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .opacity(helloAppeared ? 1 : 0)
                .offset(y: helloAppeared ? 0 : 14)
                .animation(entrance(delay: 0.35), value: helloAppeared)
            Text(L10n.t("onboarding_hello_sub"))
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .opacity(helloAppeared ? 1 : 0)
                .offset(y: helloAppeared ? 0 : 14)
                .animation(entrance(delay: 0.5), value: helloAppeared)
            Button(L10n.t("onboarding_go")) { advance(.cli) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 10)
                .opacity(helloAppeared ? 1 : 0)
                .animation(entrance(delay: 0.7), value: helloAppeared)
        }
        .onAppear { helloAppeared = true }
    }

    /// Spring-Animation mit Verzögerung — bei „Bewegung reduzieren" keine.
    private func entrance(delay: Double) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.75).delay(delay)
    }

    // MARK: Schritt 1 — CLI-Check (automatisches „little win")

    private var cliStep: some View {
        VStack(spacing: 16) {
            stepHeader(L10n.t("onboarding_cli_title"), L10n.t("onboarding_cli_sub"))
            VStack(spacing: 10) {
                ForEach(Array(model.providers.enumerated()), id: \.element.id) { index, provider in
                    CLIRow(model: model, provider: provider, delay: Double(index) * 0.35)
                }
            }
            .frame(maxWidth: 380)
            continueButton { advance(.account) }
        }
    }

    // MARK: Schritt 2 — Erster Account (die eine Kernaktion)

    private var accountStep: some View {
        VStack(spacing: 16) {
            stepHeader(L10n.t("onboarding_account_title"), L10n.t("onboarding_account_sub"))
            HStack(spacing: 16) {
                ForEach(model.providers, id: \.id) { provider in
                    providerCard(provider)
                }
            }
            if let message = model.statusMessage {
                Text(message).font(.callout).foregroundStyle(.white.opacity(0.7))
            }
            if totalAccounts > 0 {
                continueButton { advance(.aha) }
            }
        }
    }

    private func providerCard(_ provider: AccountProvider) -> some View {
        let inProgress = model.loginInProgress.contains(provider.id)
        let cliMissing = model.cliFound[provider.id] == false
        return Button {
            model.addAccount(for: provider)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: inProgress ? "globe" : "person.crop.circle.badge.plus")
                    .font(.system(size: 34, weight: .light))
                    .symbolEffect(.pulse, isActive: inProgress)
                Text(provider.displayName).font(.headline)
                if inProgress {
                    Text(L10n.t("onboarding_waiting"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                } else if cliMissing {
                    Text(L10n.t("cli_not_found"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    // Bereits verbundene Accounts dieses Anbieters (maskiert je nach Einstellung).
                    let handles = model.accounts(for: provider).map { model.displayHandle($0.handle) }
                    Text(handles.isEmpty ? " " : handles.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .frame(width: 220, height: 130)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(inProgress ? 0.45 : 0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(inProgress || cliMissing)
    }

    // MARK: Schritt 3 — Aha-Moment (Usage-Reveal)

    private var ahaStep: some View {
        VStack(spacing: 16) {
            stepHeader(L10n.t("onboarding_aha_title"), L10n.t("onboarding_aha_sub"))
            if let account = model.state.accounts.last {
                UsageRevealCard(model: model, account: account, reduceMotion: reduceMotion)
            }
            HStack(spacing: 12) {
                Button(L10n.t("onboarding_add_more")) { advance(.account) }
                    .buttonStyle(.bordered)
                continueButton { advance(.permissions) }
            }
        }
    }

    // MARK: Schritt 4 — Berechtigungen (Priming nach dem Aha)

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            stepHeader(L10n.t("onboarding_perm_title"), "")
            VStack(spacing: 12) {
                permissionCard(
                    symbol: "bell.badge",
                    text: L10n.t("onboarding_perm_notif"),
                    // Wurde die Berechtigung früher abgelehnt, kann macOS keinen Dialog mehr
                    // zeigen — dann öffnen sich die Systemeinstellungen und dieser Hinweis
                    // erklärt, was dort zu tun ist.
                    hint: model.notificationsEnabled && !model.notificationsAuthorized
                        ? L10n.t("notif_denied_hint") : nil,
                    isOn: Binding(
                        get: { model.notificationsActive },
                        set: { model.setNotificationsEnabled($0) }))
                permissionCard(
                    symbol: "arrow.clockwise.circle",
                    text: L10n.t("onboarding_perm_launch"),
                    hint: nil,
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }))
            }
            .frame(maxWidth: 420)
            continueButton { advance(.finale) }
        }
        // Solange dieser Schritt offen ist, den System-Status alle 2 s abgleichen — der
        // Toggle springt dann von allein um, sobald die Berechtigung erteilt wurde.
        .task {
            while !Task.isCancelled {
                model.syncNotifications()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func permissionCard(
        symbol: String, text: String, hint: String?, isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title2).frame(width: 34)
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 46)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
    }

    // MARK: Schritt 5 — Finale

    private var finaleStep: some View {
        VStack(spacing: 16) {
            BouncingArrow(paused: reduceMotion)
            Text(L10n.t("onboarding_done_title"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(L10n.t("onboarding_done_sub"))
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
            Button(L10n.t("onboarding_done")) { close() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
    }

    // MARK: Bausteine

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func continueButton(_ action: @escaping () -> Void) -> some View {
        Button(L10n.t("onboarding_continue"), action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
    }

    private var footer: some View {
        ZStack {
            // Progress-Dots mittig.
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(.white.opacity(s == step ? 0.95 : 0.3))
                        .frame(width: 6.5, height: 6.5)
                }
            }
            // Überspringen links — Entwickler hassen Zwangs-Touren. Esc funktioniert immer.
            HStack {
                if step != .finale {
                    Button(L10n.t("onboarding_skip")) { close() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.55))
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
            }
        }
    }
}

// MARK: - CLI-Zeile mit gestaffeltem Einblenden

private struct CLIRow: View {
    let model: AppModel
    let provider: AccountProvider
    let delay: Double
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            if let found = model.cliFound[provider.id], appeared {
                Image(systemName: found ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(found ? .green : .red)
                    .font(.title3)
                    .transition(.scale.combined(with: .opacity))
                Text(provider.displayName).font(.headline)
                Text(found ? L10n.t("cli_found") : L10n.t("cli_not_found"))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if !found {
                    Button(L10n.t("install_cli")) { NSWorkspace.shared.open(provider.installURL) }
                        .buttonStyle(.bordered)
                }
            } else {
                ProgressView().controlSize(.small)
                Text(provider.displayName).font(.headline)
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        .task {
            // Gestaffelt einblenden — der „kleine Sieg" ohne eigenes Zutun.
            try? await Task.sleep(for: .seconds(delay))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

// MARK: - Aha-Karte: Usage zählt von 0 auf die Live-Werte hoch

private struct UsageRevealCard: View {
    let model: AppModel
    let account: Account
    let reduceMotion: Bool
    @State private var revealed = false

    private var snapshot: AccountUsage? { model.usage[account.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.displayHandle(account.handle)).font(.headline)
                Spacer()
                Text(model.provider(account.provider)?.displayName ?? account.provider)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let snapshot, snapshot.known, let provider = model.provider(account.provider) {
                ForEach(
                    [
                        (UsageWindowKey.session, provider.sessionWindowLabel),
                        (UsageWindowKey.weekly, provider.weeklyWindowLabel),
                    ], id: \.0
                ) { key, label in
                    if let pct = snapshot.pct(key) {
                        usageBar(label: label, pct: pct)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("usage_unknown")).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(18)
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.14), .white.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .onAppear { reveal() }
        .onChange(of: snapshot?.known ?? false) { _, known in
            if known { reveal() }
        }
    }

    private func reveal() {
        guard snapshot?.known == true, !revealed else { return }
        if reduceMotion {
            revealed = true
        } else {
            withAnimation(.spring(duration: 1.1)) { revealed = true }
        }
    }

    private func usageBar(label: String, pct: Double) -> some View {
        let shown = revealed ? pct : 0
        return HStack(spacing: 10) {
            Text(label)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 26, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(pct >= 85 ? Color.red : (pct >= 60 ? .orange : .green))
                        .frame(width: max(6, geo.size.width * shown / 100))
                }
            }
            .frame(height: 8)
            Text("\(Int(shown))%")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .contentTransition(.numericText())
                .frame(width: 44, alignment: .trailing)
        }
    }
}

// MARK: - Hintergrund + Finale-Pfeil

/// Langsam wabernder Indigo-Gradient (Arcs „Filmvorspann"-Gefühl) — pures SwiftUI,
/// kein Asset. Bei Reduce-Motion steht er still.
private struct AnimatedGradient: View {
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / 9
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.11, blue: 0.42),
                    Color(red: 0.31, green: 0.26, blue: 0.90),
                    Color(red: 0.05, green: 0.04, blue: 0.13),
                ],
                startPoint: UnitPoint(x: 0.5 + 0.45 * cos(t), y: 0.5 + 0.45 * sin(t)),
                endPoint: UnitPoint(x: 0.5 - 0.45 * cos(t), y: 0.5 - 0.45 * sin(t))
            )
        }
        .ignoresSafeArea()
    }
}

/// Sanft auf- und abwippender Pfeil Richtung Menüleiste — beantwortet die Kernfrage
/// jeder Menüleisten-App: „Und wo lebt sie jetzt?"
private struct BouncingArrow: View {
    let paused: Bool
    @State private var up = false

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 40, weight: .semibold))
            .offset(y: up ? -7 : 7)
            .onAppear {
                guard !paused else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}
