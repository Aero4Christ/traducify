import SwiftUI

/// First-run flow inside the panel: API key + model choice, nothing else.
struct SetupView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Welcome to Traducify")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Live translation for anything your Mac plays - meetings, videos, calls. " +
                 "Transcription runs locally; only the text goes to the translator you connect.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Paste your OpenRouter API key")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                SecureField("sk-or-…", text: $state.apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Link("No key yet? Create one free at openrouter.ai/keys",
                     destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("2. Pick a transcription model (downloads once)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Picker("", selection: $state.config.whisperModel) {
                    ForEach(WhisperModel.all) { model in
                        Text(model.label).tag(model.file)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("3. Languages")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                HStack {
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
                }
                .font(.caption)
            }

            Button {
                state.completeSetup()
            } label: {
                Text("Start Translating")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(state.apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
