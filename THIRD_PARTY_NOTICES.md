# Third-Party Notices

StillMind includes or integrates with third-party components. Check the upstream
licenses before redistributing binaries, model weights, or modified versions.

## Cactus

The app integrates the Cactus iOS framework for on-device transcription.

- Source: https://github.com/cactus-compute/cactus
- Vendored path: `StillMind/Frameworks/cactus-ios.xcframework`

## Whisper-Derived Transcription Model

The bundled `StillMind/CactusTranscriptionModel` assets are derived from a
Cactus-compatible INT4 `openai/whisper-tiny` transcription model.

- Upstream model family: https://huggingface.co/openai/whisper-tiny
- Vendored path: `StillMind/CactusTranscriptionModel`

## Core ML Tagging Model

The app includes a Core ML tagging and mood classification package at
`StillMind/StillMindTagger.mlpackage`.

Contributors should document the training data, source model, and license before
publishing releases that include updated model weights.
