# DaemonFlow

Local voice-to-text for macOS. Hold **Fn**, speak, release — clean text appears in whatever app you're typing in. Everything runs on-device: Whisper for transcription, a local MLX LLM for cleanup. No audio or text ever leaves your Mac.

## Download

**[⬇ Download DaemonFlow v1.0.0](dist/DaemonFlow-v1.0.0-macOS.zip)** (macOS, Apple Silicon)

1. Unzip and drag `DaemonFlow.app` into `/Applications`.
2. First launch: the app isn't notarized yet, so **right-click → Open → Open** (or run `xattr -cr /Applications/DaemonFlow.app` once).
3. Follow the in-app setup — it walks you through granting Accessibility, Input Monitoring, and Microphone, then downloading a Whisper model and a cleanup model.

## Features

- **Push-to-talk dictation** — hold Fn to record, release to transcribe and paste into the frontmost app. Double-tap Fn for hands-free mode.
- **Local transcription** — [whisper.cpp](https://github.com/ggerganov/whisper.cpp) with Metal acceleration; pick the Whisper model size that fits your Mac.
- **LLM cleanup** — a local MLX model (e.g. Llama 3.2 3B) strips filler words ("um", "uh", "like"), resolves self-corrections ("tomorrow — no wait, today"), and adds punctuation, while keeping your tone intact.
- **⌥1 refine** — select any text you've typed in any app, press Option+1, and it's replaced in place with a cleaned-up version.
- **Floating HUD** — a small pill above the Dock shows a live waveform while recording, a spinner while transcribing, and a shimmer while refining.
- **Menu bar app** — no Dock icon, no window clutter.

## Building from source

Requires Xcode 26+ (project currently builds against the macOS 27 SDK).

```sh
git clone --recurse-submodules https://github.com/kaihere14/DaemonFlow.git
cd DaemonFlow
./scripts/build-whisper.sh        # builds whisper.cpp static libs (cmake required)
./scripts/build-and-install.sh    # Release build → /Applications/DaemonFlow.app
```

Models are downloaded on first run into `~/Library/Application Support/DaemonFlow/`.

## Privacy

Everything is processed locally. The only network access is downloading models from Hugging Face on first setup.
