# Traducify

> **Beta.** From *traducir*, Spanish for "to translate."

**Live translation for anything your Mac plays.** Traducify sits in a sleek panel at the top of your screen (right against the notch on MacBooks) and translates any audio coming out of your speakers in real time: Google Meet, Zoom, FaceTime, YouTube, movies, anything. It can also translate your own voice for the other side of a conversation, and lets you type a message and read off the translation.

- **Any audio source.** If your Mac plays it, Traducify translates it. No virtual audio drivers, no loopback setup; one permission click.
- **Any language pair.** Pick what they speak (or auto-detect) and what you read. 24 languages.
- **Private by design.** Transcription runs entirely on your Mac with whisper.cpp (Metal accelerated). Only the transcribed *text* is sent to the translation API you connect.
- **Conversation mode.** Toggle the mic and your own speech gets translated the other way, with a full bilingual transcript saved per session.
- **Type to translate.** The keyboard button opens a chat box: type in your language, read it to them in theirs, or copy it into the meeting chat.
- **Bring your own AI.** Works out of the box with a free OpenRouter account; developers can point it at any OpenAI-compatible endpoint (OpenAI, Groq, a local server…).

## Requirements

- macOS 14 (Sonoma) or newer
- Apple Silicon Mac (M1 or newer)
- A free [OpenRouter](https://openrouter.ai) account (or any OpenAI-compatible API)

## Install

1. Download `Traducify.dmg` from the [latest release](https://github.com/Aero4Christ/traducify/releases).
2. Open it and drag **Traducify** into **Applications**.
3. First launch: **right-click Traducify.app and choose Open**, then click Open in the dialog. (The beta is not notarized with Apple yet, so macOS warns once. Right-click Open is the official escape hatch.)
4. Traducify appears as a globe in your menu bar, and the panel shows up at the top of your screen.

### One-time setup (about 2 minutes)

1. **Get an API key.** Create a free account at [openrouter.ai](https://openrouter.ai), then make a key at [openrouter.ai/keys](https://openrouter.ai/keys). The free models cost nothing; the default paid model (Claude Haiku) costs roughly $0.05-0.10 per meeting hour and translates noticeably better. Your key is stored in the macOS Keychain, never in a file.
2. **Paste the key** into the welcome panel.
3. **Pick a transcription model.** "Best" (1.5 GB) for quality, "Light" (466 MB) for smaller/slower Macs. It downloads once and lives on your Mac.
4. **Pick languages**: what they speak (or Auto-detect) and what you read.
5. Click **Start Translating**. macOS will ask for **Screen & System Audio Recording** permission; allow it and reopen the app when prompted. This permission is how Traducify hears your speakers. It never looks at your screen.

That's it. Play something in another language and watch the panel.

## Using it

| Control | What it does |
|---|---|
| Green dot + status | Pipeline state at a glance |
| Mic button | Conversation mode: your speech is translated the other way too |
| Keyboard button | Chat box: type in your language, read or copy the translation |
| Gear | Settings: languages, model, sensitivity, provider |
| Chevron | Collapse to a slim ticker that still shows the latest translation |

Transcripts (when enabled) are saved to `~/Documents/Traducify/` as Markdown, one file per session.

### Tips

- **Wear headphones in two-way conversations.** Otherwise your mic hears the meeting audio and things get translated twice.
- If it clips the start of sentences, lower the sensitivity slider (more negative = more sensitive) in Settings.
- The collapsed ticker is great for movies: one quiet line at the top of the screen.

## Premium model (optional)

Settings → Translator → "Premium model". Give it a base URL, a model, and its own API key, and every translation tries it first, with the regular chain as the automatic fallback. Typical setup: an OpenAI key + `gpt-5.5` for quality, OpenRouter free models as the safety net when credits run out.

## Bring your own provider (Advanced)

Settings → Translator → Advanced. Set any OpenAI-compatible base URL and model, for example:

| Provider | Base URL | Model example |
|---|---|---|
| OpenRouter (default) | `https://openrouter.ai/api/v1` | `anthropic/claude-haiku-4.5` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |
| Groq | `https://api.groq.com/openai/v1` | `llama-3.3-70b-versatile` |
| Local (LM Studio, Ollama…) | `http://localhost:1234/v1` | whatever you run |

With no custom model set, Traducify uses a fallback chain: Claude Haiku 4.5 → Gemini Flash Lite → free Llama 3.3 70B → free Gemma 3 27B, so it degrades gracefully if a model is down or credits run out.

## Troubleshooting

- **"Screen & System Audio Recording permission needed"**: System Settings → Privacy & Security → Screen & System Audio Recording → enable Traducify, then quit and reopen it.
- **Translations stopped / "translation failed"**: usually the API key (typo, revoked) or OpenRouter credits. Check Settings → Translator.
- **Nothing happens on quiet speech**: lower the sensitivity in Settings.
- **It translates its own output / doubles up**: wear headphones in conversations, and keep conversation mode off when you are just watching a video.

## Build from source

No Xcode needed, just the Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/Aero4Christ/traducify.git
cd traducify
./scripts/build-app.sh        # builds dist/Traducify.app
cp -R dist/Traducify.app /Applications/
```

whisper.cpp is consumed as a prebuilt xcframework via SwiftPM, so the first build only downloads it; nothing C++ gets compiled on your machine.

## How it works

```
Speakers ──ScreenCaptureKit──┐
                             ├── VAD segmenter ── whisper.cpp (local, Metal) ── your AI provider ── notch panel
Microphone ──AVAudioEngine───┘                                                                      + transcript
```

## Privacy

- Audio never leaves your Mac. Transcription is local.
- Only transcribed text is sent to the translation provider you configured.
- Your API key lives in the macOS Keychain.
- No analytics, no telemetry, no accounts.

## Roadmap

- Movable / repositionable panel
- Notarized builds
- Text-to-speech for chat translations
- Intel Mac builds
- Companion mobile app (point your phone at the TV)

## License

MIT. Built by [Aero4Christ](https://github.com/Aero4Christ).
