import AppKit
import SwiftUI

/// Records a new global shortcut: press the combination you want, and it is tried
/// at once. Drawn in the panel, like `ConfirmSheet`, never as a system window.
struct ShortcutRecorderSheet: View {
    @ObservedObject var shortcut: GlobalShortcut
    let onClose: () -> Void

    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)

            VStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 22))
                    .foregroundStyle(BarStyle.candyPink)

                Text("Press a new shortcut")
                    .font(.system(size: 13, weight: .semibold))

                Text(shortcut.combo.display)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.12)))

                Text(problem ?? "Opens Note Bubble from any app. Include ⌘, ⌥ or ⌃. Esc closes.")
                    .font(.system(size: 11))
                    .foregroundStyle(problem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Use ⌥Space") { record(.standard) }
                        .disabled(shortcut.combo == .standard)
                    Button("Done", action: close)
                }
                .controlSize(.small)
            }
            .padding(18)
            .frame(maxWidth: 260)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
        }
        .transition(.opacity)
        .onAppear(perform: startListening)
        .onDisappear(perform: stopListening)
    }

    /// Key presses are taken before anything else in the panel sees them, so the
    /// combination being recorded cannot also act — ⌘N must not make a note.
    private func startListening() {
        // The current shortcut is let go of while recording, or pressing it to
        // re-record it would fold the panel away instead.
        shortcut.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags
            if event.keyCode == 53, flags.intersection([.command, .option, .control, .shift]).isEmpty {
                MainActor.assumeIsolated { close() }
                return nil
            }
            let combo = KeyCombo(
                keyCode: event.keyCode,
                command: flags.contains(.command),
                option: flags.contains(.option),
                control: flags.contains(.control),
                shift: flags.contains(.shift),
                characters: event.charactersIgnoringModifiers
            )
            MainActor.assumeIsolated { record(combo) }
            return nil
        }
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        shortcut.resume()
    }

    private func record(_ combo: KeyCombo) {
        guard combo.isAcceptable else {
            problem = "\(combo.display) would fire whenever you typed it. Add ⌘, ⌥ or ⌃."
            return
        }
        // `change` registers whichever one it ends up with — the new one, or the
        // old one back if the new one was refused. Recording goes on either way,
        // so it is let go of again until the sheet closes.
        let accepted = shortcut.change(to: combo)
        shortcut.pause()
        problem = accepted ? nil : "\(combo.display) is taken by another app. Try another."

    }

    private func close() {
        stopListening()
        onClose()
    }
}
