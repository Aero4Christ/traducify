import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var state: AppState
    let notchInset: CGFloat
    @State private var chatText = ""

    private var theme: Theme { Theme(state.config) }

    var body: some View {
        VStack(spacing: 0) {
            // keep content out from behind the camera housing
            Spacer().frame(height: notchInset > 0 ? notchInset + 2 : 8)

            header

            if !state.collapsed {
                switch state.phase {
                case .setup: SetupView(state: state)
                case .downloading: downloading
                case .loading: loadingView
                case .failed(let message): failed(message)
                case .running: feed
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(panelShape)
    }

    private var panelShape: some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0, bottomLeading: 18, bottomTrailing: 18, topTrailing: 0))
        return shape
            .fill(theme.bg.opacity(theme.opacity))
            .overlay(shape.strokeBorder(theme.textColor(0.12), lineWidth: 1))
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            if state.collapsed, let last = state.lines.last {
                Text(last.translation)
                    .font(.system(size: theme.size(12), weight: .medium))
                    .foregroundStyle(theme.textColor(0.9))
                    .lineLimit(1)
            } else {
                Text(state.status)
                    .font(.caption)
                    .foregroundStyle(theme.textColor(0.55))
                    .lineLimit(1)
            }

            Spacer()

            if case .running = state.phase, !state.collapsed {
                iconButton(state.paused ? "play.fill" : "pause.fill",
                           on: state.paused,
                           help: state.paused ? "Resume translating" : "Pause translating") {
                    state.togglePause()
                }
                iconButton(state.config.micEnabled ? "mic.fill" : "mic.slash",
                           on: state.config.micEnabled,
                           help: "Conversation mode: also translate your own voice") {
                    state.toggleMic()
                }
                iconButton("keyboard", on: state.showChat,
                           help: "Type something for them to read in their language") {
                    state.showChat.toggle()
                }
            }

            if !state.collapsed {
                iconButton("gearshape", on: false, help: "Settings") { state.onOpenSettings?() }
            }

            iconButton(state.collapsed ? "chevron.down" : "chevron.up", on: false,
                       help: state.collapsed ? "Expand" : "Collapse to a single line") {
                state.collapsed.toggle()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func iconButton(_ name: String, on: Bool, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .foregroundStyle(on ? theme.accent : theme.textColor(0.45))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var statusColor: Color {
        switch state.phase {
        case .running: return state.paused ? .orange : theme.accent
        case .failed: return .red
        default: return .yellow
        }
    }

    // MARK: - phases

    private var downloading: some View {
        VStack(spacing: 10) {
            ProgressView(value: state.downloadProgress).tint(theme.accent)
            Text("\(Int(state.downloadProgress * 100))% - one-time download, the model lives on your Mac")
                .font(.caption)
                .foregroundStyle(theme.textColor(0.5))
        }
        .padding(20)
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(state.status).font(.caption).foregroundStyle(theme.textColor(0.5))
        }
        .padding(20)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.callout)
                .foregroundStyle(theme.textColor(0.85))
                .multilineTextAlignment(.center)
            HStack {
                Button("Try Again") { state.bootstrap() }
                Button("Settings…") { state.onOpenSettings?() }
            }
        }
        .padding(16)
    }

    // MARK: - running feed

    private var feed: some View {
        VStack(spacing: 8) {
            if state.lines.isEmpty && state.chatResult == nil {
                Text("Play or say something - translations appear here")
                    .font(.callout)
                    .foregroundStyle(theme.textColor(0.35))
                    .padding(.vertical, 10)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(state.lines.suffix(8)) { line in
                                LineView(line: line, theme: theme)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                    }
                    .onChange(of: state.lines) {
                        if let last = state.lines.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            if let chat = state.chatResult {
                ChatResultView(line: chat, theme: theme,
                               targetLang: state.config.theirLanguage) { state.chatResult = nil }
            }

            if state.showChat {
                chatBar
            } else {
                Spacer().frame(height: 4)
            }
        }
    }

    private var chatBar: some View {
        HStack(spacing: 8) {
            TextField("Type to translate for them…", text: $chatText)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(theme.textColor(0.08)))
                .onSubmit { submitChat() }
            Button {
                submitChat()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(chatText.isEmpty ? theme.textColor(0.25) : theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func submitChat() {
        state.sendChat(chatText)
        chatText = ""
    }
}

/// One translated utterance: big translation, small original. While the
/// translation is still streaming in, the original shows dimmed in its place.
struct LineView: View {
    let line: TranslationLine
    let theme: Theme

    private var streaming: Bool { line.translation.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(streaming ? line.original : line.translation)
                .font(.system(size: theme.size(line.speaker == .them ? 16 : 13),
                              weight: .medium))
                .foregroundStyle(streaming ? theme.textColor(0.4)
                                           : theme.textColor(line.speaker == .them ? 1.0 : 0.75))
                .textSelection(.enabled)
            if !streaming {
                Text("\(line.speaker == .them ? "" : "you: ")\(line.original)")
                    .font(.caption)
                    .foregroundStyle(theme.textColor(0.35))
                    .lineLimit(2)
            }
        }
        .id(line.id)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chat translation shown big enough to read aloud, with copy + speak buttons.
struct ChatResultView: View {
    let line: TranslationLine
    let theme: Theme
    let targetLang: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Read, play, or paste this:")
                    .font(.caption2)
                    .foregroundStyle(theme.textColor(0.4))
                Spacer()
                Button {
                    Speech.shared.speak(line.translation, langCode: targetLang)
                } label: {
                    Label("Speak", systemImage: "speaker.wave.2.fill").font(.caption)
                }
                .buttonStyle(.borderless)
                .tint(theme.accent)
                .disabled(line.translation.isEmpty)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(line.translation, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.borderless)
                .tint(theme.accent)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textColor(0.3))
                }
                .buttonStyle(.plain)
            }
            Text(line.translation.isEmpty ? line.original : line.translation)
                .font(.system(size: theme.size(18), weight: .semibold))
                .foregroundStyle(line.translation.isEmpty ? theme.textColor(0.4) : theme.accent)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.textColor(0.06)))
        .padding(.horizontal, 14)
    }
}
