# MyNotes

Notes, a scroll away. Quick notes when you need them.

MyNotes is a small, local-first notes app for macOS. It gives you a quick place to capture and find plain-text notes, with an optional clipboard history kept on your Mac.

> MyNotes is under active development and is currently built for personal use. The quick-access interaction is inspired by Unclutter; MyNotes is an independent project and is not affiliated with it.

## Features

- Reveal a compact, floating Quick Notes panel by moving the pointer to the top edge and scrolling down.
- Run MyNotes from the menu bar instead of keeping a Dock icon, with actions for Quick Notes, the Notes Library, Settings, and Quit.
- Show optional whole-Mac CPU, memory, and best-effort GPU usage in the Quick Notes header, plus a manual coffee toggle to prevent idle sleep while it is active.
- Tune the floating panel’s glass level and show/hide animation speed in Appearance settings.
- Record microphone audio in Meeting Capture, pause/resume, and transcribe locally with macOS Speech assets; review, copy, and save a timestamped transcript as a normal note.
- Create, edit, search, browse, and delete notes.
- Copy selected note text directly; a selection that remains unchanged for one second is copied automatically into the system clipboard.
- Use Command-C, Command-Z, and Command-Shift-Z for standard copy, undo, and redo in note editing.
- Read and write ordinary UTF-8 `.txt` files in a folder you choose.
- Search note titles and contents from the library or Quick Notes panel.
- Optionally keep up to 100 recent clipboard items (text, images, and copied files), search them, and restore or remove them.
- Use the native macOS light, dark, and system appearances, with accent-color settings.
- Keep note and clipboard data local. No account, sync service, or server is used.

## Requirements

- macOS 26 or later. The package deployment target is macOS 26; the app is intended to run on later macOS releases as well. It has been built on macOS 27.0.1.
- Xcode or Apple command-line developer tools providing Swift 6.2 or later and `xcrun actool` (used to build the app icon).
- Meeting Capture requires macOS microphone and Speech Recognition permission, plus installed local macOS Speech assets for a supported language.

## Build and run

Clone the repository, then build and install the app in your user Applications folder:

```sh
git clone https://github.com/vinukj/MyNotes.git
cd MyNotes
swift test
./build.sh --open
```

`build.sh` creates `~/Applications/MyNotes.app`. It uses a development signing identity when one is available, otherwise it signs the app ad hoc for local use. Build products are stored outside the repository in `~/Library/Developer/MyNotes/build`.

Other useful commands:

```sh
./build.sh           # Release build and install, without opening the app
./build.sh --debug   # Debug build and install
swift test           # Run the package's automated tests
```

The install script replaces the existing `~/Applications/MyNotes.app` bundle when installing an update. It does not move or delete your notes or clipboard-history data.

## Using MyNotes

- **Open MyNotes:** Click its menu-bar icon to show Quick Notes, open the Notes Library or Settings, or quit. MyNotes stays available in the menu bar without a Dock icon.
- **Quick Notes gesture:** Move the pointer to the top edge of a display, then scroll down. The gesture can be turned off in Settings. You can also use **Show Quick Notes** from the menu-bar menu or press **Command-Shift-N**.
- **Quick Notes status:** Choose the CPU, memory, GPU, and coffee indicators in **Settings → General**. The coffee control is manual and prevents idle sleep only while enabled; hiding it in Settings releases that assertion. GPU availability depends on Mac hardware and system telemetry.
- **Tune the panel:** Adjust the glass level and show/hide animation speed in **Settings → Appearance**.
- **Record a meeting transcript:** Open Quick Notes with the top-edge gesture, then choose the waveform button. Enter an optional agenda, grant microphone and Speech Recognition access when prompted, and install the local Speech assets if MyNotes reports they are missing. Start, pause/resume, then stop to transcribe. Review or edit the transcript, copy its Markdown, or create a regular `.txt` note titled with the agenda and recording timestamp. MyNotes temporarily writes microphone audio to a private temporary file for local processing and removes it after processing or on a later app launch if the app exits unexpectedly.
- **Meeting Capture scope:** The current implementation records the Mac microphone and uses installed macOS Speech transcription assets. It does not directly capture system audio, identify speakers, generate AI summaries/action items, or export a meeting PDF yet. Remote participants may be audible through the microphone only when played aloud near the microphone.
- **Edit and copy:** Select text in a note body to show the Copy action; if the selection stays unchanged for one second it is automatically copied. Note editing also supports Command-C, Command-Z, and Command-Shift-Z.
- **Create a note:** Choose **New Note** or press **Command-N**. A note's title becomes its filename; its text is the file contents.
- **Search notes:** Search matches note titles and contents locally; entering a URL searches note text and does not open or fetch the address. Use the **×** button to clear Quick Notes search. Press **Command-F** to focus search.
- **Browse notes:** Choose **Open Notes Library** from the MyNotes menu-bar menu to see the full notes library.
- **Choose storage:** Open **Settings → Storage → Choose Folder…**. MyNotes reads and writes top-level `.txt` files in that folder. Changing the folder switches the active library; it does not move files from the previous folder.
- **Use clipboard history:** Open the clipboard view from Quick Notes and enable history when prompted, or turn it on in **Settings → General**. Click an item to copy it back to the system clipboard. The clipboard gear opens storage settings.
- **Delete:** Use a note's trash button or the selected-note Delete command. Deleting a note removes its `.txt` file from the notes folder. Clipboard items can be removed individually or cleared from the clipboard view/settings.

## Where your data lives

Notes are ordinary UTF-8 `.txt` files stored directly in the selected Notes Folder. Existing top-level `.txt` files are loaded as notes; the filename (without `.txt`) is the title. Nested folders and non-UTF-8 text files are not imported as notes.

By default, the Notes Folder is:

```text
~/Library/Application Support/MyNotes/
```

Clipboard history is separate from note files. When enabled, it is stored in `ClipboardHistory.store` inside the selected Notes Folder. Clipboard history is off by default and retains up to 100 recent items. Copies marked as sensitive, transient, or automatically generated, and copies identified as coming from supported password managers, are skipped. Turning history off stops new captures; existing history stays on disk until you clear it.

MyNotes does not upload your notes, clipboard history, meeting audio, or transcript. Meeting audio is temporarily written locally for transcription and removed afterward; the saved transcript is an ordinary plain-text note in the selected Notes Folder. Anyone or any backup/sync tool with access to the selected folder may also be able to read those notes, so choose a folder whose access and backup behavior you trust.

## Tests and development

Run the package tests before submitting a change:

```sh
swift test
```

The app also includes helper scripts for local development:

- `tools/selftest.sh` runs app-level checks against a temporary test store. It expects the installed app and clears MyNotes saved window state before running.
- `tools/snap.sh` captures UI snapshots for design review. Snapshot and seed modes require an explicit test store under `/tmp`; do not point them at your real notes folder.
- `tools/grid-lint.sh` and `tools/check-layout.swift` support layout checks for captured snapshots.
- `tools/make_icon.sh` rebuilds the app icon from the source in `Icon/AppIcon.icon/`.

Please keep changes focused, run the relevant tests, and include steps to reproduce UI or storage changes when opening an issue or pull request.

## Project layout

```text
Sources/MyNotes/       macOS app, windows, settings, clipboard history, meeting capture
Sources/MyNotesKit/    note-file storage, meeting transcript rendering, UI-independent helpers
Tests/MyNotesKitTests/ automated package tests
Icon/                  editable Icon Composer source
docs/                  product brief, user stories, glossary, and fix notes
tools/                 build, test, icon, and UI-review helpers
Package.swift          Swift Package manifest
build.sh               local build and install script
```

## License

This repository does not currently include a license. Until a license is added, permission to reuse, modify, or redistribute the code is not granted.

## Acknowledgments

The quick-access notes interaction takes inspiration from [Unclutter](https://unclutterapp.com/). MyNotes is a separate, independent macOS app.
