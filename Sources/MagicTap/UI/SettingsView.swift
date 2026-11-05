import Combine
import MagicTapCore
import SwiftUI

/// The window content: gestures, live viewer and first-run setup.
struct SettingsView: View {
    @ObservedObject private var nav = Navigation.shared

    var body: some View {
        TabView(selection: $nav.tab) {
            GesturesTab().tabItem { Label("Gestures", systemImage: "hand.tap") }.tag(Navigation.Tab.gestures)
            LiveTab().tabItem { Label("Live", systemImage: "waveform") }.tag(Navigation.Tab.live)
            SetupTab().tabItem { Label("Setup", systemImage: "checkmark.shield") }.tag(Navigation.Tab.setup)
        }
        .padding(16)
        .frame(width: 560, height: 520)
    }
}

// MARK: Gestures

private struct GesturesTab: View {
    @AppStorage(Settings.Key.enabled) private var enabled = true
    @AppStorage(Settings.Key.leftTap) private var leftTap = true
    @AppStorage(Settings.Key.rightTap) private var rightTap = true
    @AppStorage(Settings.Key.threeFingerAction) private var threeFinger = ThreeFingerAction.showDesktop.rawValue
    @AppStorage(Settings.Key.doubleTap) private var doubleTap = true
    @AppStorage(Settings.Key.tapAndDrag) private var tapAndDrag = true
    @AppStorage(Settings.Key.holdToDrag) private var holdToDrag = true
    @AppStorage(Settings.Key.missionControlSwipe) private var missionControl = true
    @AppStorage(Settings.Key.pinchZoom) private var pinch = true
    @AppStorage(Settings.Key.navigationSwipe) private var navigation = true

    @AppStorage(Settings.Key.maxTapDuration) private var maxTapDuration = TapConfig().maxTapDuration
    @AppStorage(Settings.Key.doubleTapWindow) private var doubleTapWindow = TapConfig().doubleTapWindow
    @AppStorage(Settings.Key.holdToDragAfter) private var holdToDragAfter = TapConfig().holdToDragAfter
    @AppStorage(Settings.Key.swipeDistance) private var swipeDistance = Double(TapConfig().swipeDistance)
    @AppStorage(Settings.Key.pinchGain) private var pinchGain = Double(TapConfig().pinchGain)
    @AppStorage(Settings.Key.edgeMargin) private var edgeMargin = Double(TapConfig().edgeMargin)

    var body: some View {
        Form {
            Section {
                Toggle("MagicTap enabled", isOn: $enabled).fontWeight(.medium)
            }
            Section("Gestures") {
                Toggle("Tap → left click", isOn: $leftTap)
                Toggle("Two-finger tap → right click", isOn: $rightTap)
                Picker("Three-finger hold", selection: $threeFinger) {
                    ForEach(ThreeFingerAction.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Double tap → double click", isOn: $doubleTap)
                Toggle("Tap, then hold → drag", isOn: $tapAndDrag)
                Toggle("Rest finger → drag", isOn: $holdToDrag)
                Toggle("Two-finger swipe up / down → Mission Control", isOn: $missionControl)
                Toggle("Two-finger pinch → zoom", isOn: $pinch)
                Toggle("One-finger swipe left / right → back / forward", isOn: $navigation)
            }
            Section("Fine tuning") {
                Slider(label: "Tap speed", value: $maxTapDuration, range: 0.12...0.35, unit: "s",
                       hint: "Longest touch that still counts as a tap.")
                Slider(label: "Double tap window", value: $doubleTapWindow, range: 0.25...0.8, unit: "s",
                       hint: "Time allowed between the two taps.")
                Slider(label: "Hold to drag", value: $holdToDragAfter, range: 0.12...0.28, unit: "s",
                       hint: "How long a resting finger waits before dragging.")
                Slider(label: "Swipe length", value: $swipeDistance, range: 0.06...0.3, unit: "",
                       hint: "Two-finger distance for Mission Control.")
                Slider(label: "Zoom speed", value: $pinchGain, range: 1...5, unit: "×",
                       hint: "How much the pinch zooms.")
                Slider(label: "Grip margin", value: $edgeMargin, range: 0.02...0.25, unit: "",
                       hint: "Contacts this close to the sides are treated as your grip.")
                HStack {
                    Spacer()
                    Button("Restore defaults") { Settings.resetTuning() }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: enabled) { _ in apply() }
        .onChange(of: threeFinger) { _ in apply() }
        .onChange(of: [leftTap, rightTap, doubleTap, tapAndDrag, holdToDrag, missionControl, pinch, navigation]) { _ in apply() }
        .onChange(of: [maxTapDuration, doubleTapWindow, holdToDragAfter, swipeDistance, pinchGain, edgeMargin]) { _ in apply() }
    }

    private func apply() {
        NotificationCenter.default.post(name: .magicTapSettingsChanged, object: nil)
    }
}

private struct Slider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value) + (unit.isEmpty ? "" : " \(unit)"))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            SwiftUI.Slider(value: $value, in: range)
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension Notification.Name {
    /// Posted when the window changes a setting, so the detector reloads its config.
    static let magicTapSettingsChanged = Notification.Name("MagicTapSettingsChanged")
}

// MARK: Live

private struct LiveTab: View {
    @ObservedObject private var live = LiveModel.shared
    @AppStorage(Settings.Key.edgeMargin) private var edgeMargin = Double(TapConfig().edgeMargin)

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            MouseView(touches: live.touches, edgeMargin: edgeMargin)
                .frame(maxHeight: 400)
            VStack(alignment: .leading, spacing: 12) {
                Text("Touch your Magic Mouse").font(.headline)
                Text("Fingers appear here as you touch it. Orange ones are on the edges and count as grip, so they are ignored.")
                    .font(.callout).foregroundStyle(.secondary)
                Text(live.touches.isEmpty ? "No fingers" : "\(live.touches.count) finger\(live.touches.count == 1 ? "" : "s")")
                    .monospacedDigit()
                Divider()
                Text("Detected gestures").font(.subheadline).fontWeight(.medium)
                if live.events.isEmpty {
                    Text("Nothing yet").foregroundStyle(.secondary)
                } else {
                    ForEach(live.events) { event in
                        HStack {
                            Text(event.text)
                            Spacer()
                            Text(event.time, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: Setup

private struct SetupTab: View {
    @State private var trusted = ClickPoster.isTrusted
    @State private var mice = LiveModel.shared.mouseCount()
    @State private var login = LoginItem.isEnabled
    @State private var loginError: String?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Two things MagicTap needs") {
                StepRow(
                    done: trusted,
                    title: "Accessibility permission",
                    detail: "Lets MagicTap click for you. Open System Settings → Privacy & Security → Accessibility and switch MagicTap on."
                ) {
                    Button("Open System Settings") {
                        ClickPoster.requestTrust()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                StepRow(
                    done: mice > 0,
                    title: "Magic Mouse connected",
                    detail: mice > 0
                        ? "Found \(mice) Magic Mouse."
                        : "Pair your Magic Mouse in System Settings → Bluetooth. MagicTap looks again every few seconds."
                ) { EmptyView() }
            }
            Section("Options") {
                Toggle("Launch at login", isOn: Binding(get: { login }, set: { newValue in
                    do {
                        try LoginItem.set(newValue)
                        loginError = nil
                    } catch {
                        loginError = "Only works from the installed app, not from `swift run`."
                    }
                    login = LoginItem.isEnabled
                }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Back / forward") {
                Text("Slide one finger left or right and MagicTap sends the same scroll gesture as a trackpad, so Chrome shows its arrow and goes back or forward if you keep going. Stop short and it cancels.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Tip") {
                Text("If MagicTap stops clicking after you update it, macOS dropped the permission: remove MagicTap from the Accessibility list and add it again.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            trusted = ClickPoster.isTrusted
            mice = LiveModel.shared.mouseCount()
            login = LoginItem.isEnabled
        }
    }
}

private struct StepRow<Action: View>: View {
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(done ? .green : .orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if !done { action() }
            }
        }
        .padding(.vertical, 2)
    }
}
