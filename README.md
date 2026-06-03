# TagFrame

TagFrame is a macOS SwiftUI app for inspecting and editing ID3 metadata in audio files. It is built around a focused desktop workflow for opening files or folders, reviewing tag structure, editing common fields, and saving updated tags back to disk.

## Features

- Open MP3 files, audio files, and folders.
- Inspect ID3 metadata in summary, raw tag, technical, and hex-oriented views.
- Edit common tag fields and embedded artwork.
- Review and edit MP3 chapters.
- Batch edit album metadata across multiple selected files.
- Identify tracks with ShazamKit and apply suggested metadata.
- Use App Intents to add or identify ID3 tags from Shortcuts.

## Requirements

- macOS with SwiftUI and ShazamKit support.
- Xcode 16 or newer is recommended.

## Building

1. Open `IDTagEditor.xcodeproj` in Xcode.
2. Let Xcode resolve the Swift Package dependency on [`mp3ChapterReader`](https://github.com/holgerkrupp/mp3ChapterReader).
3. Select the `IDTagEditor` scheme.
4. Build and run the app.

## Development Notes

The project is organized as a native SwiftUI app:

- `IDTagEditor/Models` contains tag parsing, editing, validation, batch editing, Shazam lookup, and save state logic.
- `IDTagEditor/Views` contains the primary app UI and reusable SwiftUI components.
- `IDTagEditor/AppIntents` exposes ID3 tagging workflows to Shortcuts.

## License

This project is available under the MIT License. See [LICENSE](LICENSE) for details.
