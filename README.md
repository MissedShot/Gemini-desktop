# GeminiChatMac

macOS chat app on SwiftUI for Xcode with Gemini API key support.

## Important Notice

- **Gemini is a trademark/product of Google** (Google LLC).
- This repository is an **independent educational project** and is **not affiliated with, endorsed by, or sponsored by Google**.
- The project is intended for learning SwiftUI/macOS development and Gemini API integration examples.

## Features

- Chat UI similar to ChatGPT format (message bubbles + input area)
- Gemini REST API integration (`generateContent`)
- Streaming assistant output (text appears while model is generating)
- Configurable model (default: `gemini-2.0-flash`)
- API key is saved locally in UserDefaults (auto-save, without Keychain)
- Load available models for your key via `ListModels`
- Clear chat and error handling

## Open in Xcode

1. Open Xcode.
2. Click **File > Open...** and select `GeminiChatMac.xcodeproj` in this folder.
3. Select scheme `GeminiChatMac` and run.

## Usage

1. Paste your Gemini API key in the top field.
2. Key is saved locally automatically.
3. Click **Load Models** to fetch models available for your API key.
4. Choose model only from the dropdown list.
5. Type message and press **Cmd+Enter** or **Send**.

## Gemini endpoint used

`POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={API_KEY}`
