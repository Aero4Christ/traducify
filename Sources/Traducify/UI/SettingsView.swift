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
                    ForEach(Language.all) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                Picker("I speak", selection: $state.config.myLanguage) {
                    ForEach(Language.all) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                Toggle("Conversation mode (translate my voice too)", isOn: $state.config.micEnabled)
            }

            Section("Transcription") {
                Picker("Whisper model", selection: $state.config.whisperModel) {
                    ForEach(WhisperModel.all) { model in
                        Text(model.label).tag(model.file)
                    }
                }
                Slider(value: $state.config.thresholdDb, in: -60...(-20), step: 1) {
                    Text("Sensitivity (\(Int(state.config.thresholdDb)) dB)")
                }
                Text("Lower = picks up quieter speech. Default -38.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Translator") {
                SecureField("API key", text: $state.apiKeyDraft)
                Link("Manage keys at openrouter.ai/keys",
                     destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.caption)
                DisclosureGroup("Advanced: bring your own provider") {
                    TextField("Base URL", text: $state.config.baseURL)
                    TextField("Model (overrides the default chain)", text: $state.config.customModel)
                    Text("Any OpenAI-compatible endpoint works: OpenRouter, OpenAI, Groq, a local server…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if state.config.baseURL != "https://openrouter.ai/api/v1",
                       state.config.customModel.trimmingCharacters(in: .whitespaces).isEmpty {
                        Label("Custom provider needs a model name. The default fallback chain only exists on OpenRouter, so without one every request will fail (usually a 404).",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
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
                    if saved {
                        Text("Saved").font(.caption).foregroundStyle(.green)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .onAppear { initialModel = state.config.whisperModel }
    }
}
