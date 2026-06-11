import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var state: AppState
    let notchInset: CGFloat
    @State private var chatText = ""

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
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0, bottomLeading: 18, bottomTrailing: 18, topTrailing: 0))
            .fill(Color.black.opacity(0.94))
            .overlay(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 0, bottomLeading: 18, bottomTrailing: 18, topTrailing: 0))
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            if state.collapsed, let last = state.lines.last {
                // ticker mode: the latest translation in one line
                Text(last.translation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            } else {
                Text(state.status)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            if case .running = state.phase, !state.collapsed {
                Button {
                    state.toggleMic()
                } label: {
                    Image(systemName: state.config.micEnabled ? "mic.fill" : "mic.slash")
                        .foregroundStyle(state.config.micEnabled ? .green : .white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Conversation mode: also translate your own voice")

                Button {
                    state.showChat.toggle()
                } label: {
                    Image(systemName: "keyboard")
                        .foregroundStyle(state.showChat ? .green : .white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Type something for them to read in their language")
            }

            if !state.collapsed {
                Button {
                    state.onOpenSettings?()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }

            Button {
                state.collapsed.toggle()
            } label: {
                Image(systemName: state.collapsed ? "chevron.down" : "chevron.up")
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch state.phase {
        case .running: return .green
        case .failed: return .red
        default: return .yellow
        }
    }

    // MARK: - phases

    private var downloading: some View {
        VStack(spacing: 10) {
            ProgressView(value: state.downloadProgress)
                .tint(.green)
            Text("\(Int(state.downloadProgress * 100))% - one-time download, the model lives on your Mac")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(20)
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(state.status)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(20)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
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
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.vertical, 10)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(state.lines.suffix(8)) { line in
                                LineView(line: line)
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
                ChatResultView(line: chat) { state.chatResult = nil }
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
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .onSubmit { submitChat() }
            Button {
                submitChat()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(chatText.isEmpty ? .white.opacity(0.25) : .green)
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

/// One translated utterance: big translation, small original.
struct LineView: View {
    let line: TranslationLine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.translation)
                .font(.system(size: line.speaker == .them ? 16 : 13, weight: .medium))
                .foregroundStyle(line.speaker == .them ? .white : .white.opacity(0.75))
                .textSelection(.enabled)
            Text("\(line.speaker == .them ? "" : "you: ")\(line.original)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(2)
        }
        .id(line.id)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chat translation shown big enough to read aloud, with one-tap copy.
struct ChatResultView: View {
    let line: TranslationLine
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Read or paste this:")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(line.translation, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .tint(.green)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            Text(line.translation)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .padding(.horizontal, 14)
    }
}
