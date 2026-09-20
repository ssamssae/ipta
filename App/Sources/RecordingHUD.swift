import AppKit
import SwiftUI

struct RecordingHUDView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .opacity(state.recording ? max(0.4, 0.4 + state.level) : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(RecordingHUD.title(for: state.phase))
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            LevelBars(level: state.recording ? state.level : 0)
                .frame(width: 76, height: 20)
            AppKitActionButton(
                title: stopTitle,
                identifier: "malgyeol-hud-stop",
                prominent: state.recording,
                danger: state.recording,
                action: { state.toggle(fromHotkey: true) }
            )
            .frame(width: 56, height: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 320, height: 56)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }

    private var dotColor: Color {
        state.recording ? .red : .orange
    }

    private var subtitle: String {
        if state.recording {
            return String(format: "%.0f초 · 같은 키로 멈춤", state.elapsed)
        }
        return "잠시만요"
    }

    private var stopTitle: String {
        state.recording ? "정지" : "취소"
    }
}

struct LevelBars: View {
    var level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<7, id: \.self) { i in
                let threshold = Double(i) / 7.0
                Capsule()
                    .fill(level > threshold ? Color.red.opacity(0.85) : Color.secondary.opacity(0.28))
                    .frame(width: 6, height: 8 + CGFloat(i) * 1.6)
            }
        }
    }
}

enum RecordingHUD {
    static func title(for phase: AppPhase) -> String {
        switch phase {
        case .recording: return "듣는 중"
        case .transcribing: return "받아적는 중"
        case .polishing: return "다듬는 중"
        case .requestingMic: return "마이크 허용"
        default: return "입타"
        }
    }

    static func shouldShow(phase: AppPhase) -> Bool {
        switch phase {
        case .recording, .transcribing, .polishing:
            return true
        default:
            return false
        }
    }

    static func statusSymbol(phase: AppPhase) -> String {
        switch phase {
        case .recording: return "waveform.circle.fill"
        case .transcribing, .polishing: return "text.alignleft"
        default: return "waveform"
        }
    }

    static func makePanel(state: AppState) -> NSPanel {
        let view = NSHostingView(rootView: RecordingHUDView(state: state))
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 56)
        let panel = NSPanel(
            contentRect: view.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        return panel
    }

    static func place(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 28
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
