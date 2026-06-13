import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var initialModel = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Languages") {
                Picker("They speak", selection: $state.config.theirLanguage) {
                    Text(Language.auto.name).tag("")
                    ForEach(Language.all) { lang in Text(lang.name).tag(lang.code) }
                }
                Picker("I speak", selection: $state.config.myLanguage) {
                    ForEach(Language.all) { lang in Text(lang.name).tag(lang.code) }
                }
                Toggle("Conversation mode (translate my voice too)", isOn: $state.config.micEnabled)
            }

            Section("Transcription") {
                Picker("Whisper model", selection: $state.config.whisperModel) {
                    ForEach(WhisperModel.all) { model in Text(model.label).tag(model.file) }
                }
                Slider(value: $state.config.thresholdDb, in: -60...(-20), step: 1) {
                    Text("Sensitivity (\(Int(state.config.thresholdDb)) dB)")
                }
                Text("Lower = picks up quieter speech. Default -38.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Translator") {
                SecureField("API key", text: $state.apiKeyDraft)
                Link("Manage keys at openrouter.ai/keys",
                     destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.caption)

                Button {
                    state.testConnection()
                } label: {
                    Label("Test Connection", systemImage: "bolt.horizontal.circle")
                }
                if let result = state.testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("Failed") ? .red
                                         : result == "testing…" ? .secondary : .green)
                        .textSelection(.enabled)
                }

                DisclosureGroup("Premium model (optional, tried first)") {
                    TextField("Base URL", text: $state.config.premiumBaseURL)
                    modelField(text: $state.config.premiumModel,
                               placeholder: "Model (e.g. gpt-4o)",
                               options: state.premiumModelOptions, premium: true)
                    SecureField("API key for this provider", text: $state.premiumKeyDraft)
                    Text("Every translation tries this first; the regular chain above is the fallback when it errors or runs out of credits.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                DisclosureGroup("Advanced: bring your own provider") {
                    TextField("Base URL", text: $state.config.baseURL)
                    modelField(text: $state.config.customModel,
                               placeholder: "Model (overrides the default chain)",
                               options: state.mainModelOptions, premium: false)
                    Text("Any OpenAI-compatible endpoint works: OpenRouter, OpenAI, Groq, a local server…")
                        .font(.caption).foregroundStyle(.secondary)
                    if state.config.baseURL != "https://openrouter.ai/api/v1",
                       state.config.customModel.trimmingCharacters(in: .whitespaces).isEmpty {
                        Label("Custom provider needs a model name. The default fallback chain only exists on OpenRouter, so without one every request will fail (usually a 404).",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            Section("Appearance") {
                ColorPicker("Background", selection: colorBinding(\.panelBgHex, default: .black))
                ColorPicker("Text", selection: colorBinding(\.panelTextHex, default: .white))
                ColorPicker("Accent", selection: colorBinding(\.accentHex, default: .green))
                Slider(value: $state.config.panelOpacity, in: 0.5...1.0) {
                    Text("Background opacity (\(Int(state.config.panelOpacity * 100))%)")
                }
                Slider(value: $state.config.fontScale, in: 0.8...1.6, step: 0.05) {
                    Text("Text size (\(Int(state.config.fontScale * 100))%)")
                }
                Button("Reset appearance") {
                    let d = Config()
                    state.config.panelBgHex = d.panelBgHex
                    state.config.panelTextHex = d.panelTextHex
                    state.config.accentHex = d.accentHex
                    state.config.panelOpacity = d.panelOpacity
                    state.config.fontScale = d.fontScale
                }
                .font(.caption)
            }

            Section("Transcripts") {
                Toggle("Save session transcripts", isOn: $state.config.saveTranscripts)
                Button("Open Transcripts Folder") {
                    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Traducify")
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
            }

            Section {
                HStack {
                    Button("Save") {
                        state.applySettings(reloadModel: initialModel != state.config.whisperModel)
                        initialModel = state.config.whisperModel
                        saved = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            saved = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onAppear { initialModel = state.config.whisperModel }
    }

    /// A model text field with a "Load" menu populated from the provider's /models.
    private func modelField(text: Binding<String>, placeholder: String,
                            options: [String], premium: Bool) -> some View {
        HStack {
            TextField(placeholder, text: text)
            if options.isEmpty {
                Button {
                    state.loadModels(premium: premium)
                } label: {
                    if state.loadingModels { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.down.circle") }
                }
                .help("Load available models from this provider")
            } else {
                Menu {
                    Button("Refresh") { state.loadModels(premium: premium) }
                    Divider()
                    ForEach(options, id: \.self) { m in
                        Button(m) { text.wrappedValue = m }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 40)
            }
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<Config, String>,
                              default fallback: Color) -> Binding<Color> {
        Binding(
            get: { Color(hex: state.config[keyPath: keyPath], default: fallback) },
            set: { state.config[keyPath: keyPath] = $0.hexString })
    }
}
