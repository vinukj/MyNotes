# Bug fixes

## 2026-11-12 — Notes fail to save after changing the Notes Folder

**Bug ID**: MYNOTES-NOTE-STORE-OWNERSHIP
**Description**: Text entered into a note could trigger “This note is not inside the selected Notes Folder,” and edits could be lost while folder changes replaced the editor.
**Root Cause**: Debounced and `onDisappear` saves used the app's current `TextNoteStore`, which may already point to a different folder than the note's file.
**Fix Applied**: Flush the selected note before switching folders and route any delayed save to the folder containing that note's `.txt` file.
**Areas Addressed**: Storage, UI, UX
**Tests Added**: `Tests/MyNotesKitTests/TextNoteStoreTests.swift` verifies a delayed save writes to the original folder and never to the newly selected folder.
**Boundary Validations**: A save arriving after a folder switch preserves title and body in the original location; the selected new folder stays unchanged.
**HITL Required**: Yes — create and type into a Quick Note, switch folders while editing, and verify both the old note and new folder contents.
**Regression Risk**: Low — normal saves still target the note's own `.txt` file; folder changes explicitly save the active note before replacing the current library.

## 2026-11-12 — Quick Notes editor closes when entering the body

**Bug ID**: MYNOTES-QUICK-NOTES-EDITOR-FOCUS
**Description**: After creating a note in Quick Notes, clicking the body editor could make the floating panel disappear before text could be entered.
**Root Cause**: The panel hid itself on every key-focus loss, including focus changes while the pointer was still inside the panel.
**Fix Applied**: Keep the panel open for key-focus loss inside its frame; preserve outside-click dismissal when focus is lost outside.
**Areas Addressed**: UI, UX
**Tests Added**: `Sources/MyNotes/SelfTest.swift` checks inside-panel and outside-panel dismissal decisions.
**Boundary Validations**: Pointer at the panel center remains visible; pointer just beyond the panel's right edge dismisses.
**HITL Required**: Yes — manually create a note in Quick Notes and type in both title and body; click outside to confirm dismissal.
**Regression Risk**: Low — this narrows only the condition that hides the panel during key-focus loss.

## 2026-11-12 — Delayed editor saves recreate deleted notes

**Bug ID**: MYNOTES-DELETED-NOTE-RESURRECTION
**Description**: Deleting the selected note could be undone when the closing editor's delayed save rewrote its `.txt` file.
**Root Cause**: `NoteEditor.onDisappear` and its debounce task can call `saveNote` after `deleteNote` has removed the file.
**Fix Applied**: Record successfully deleted note IDs and ignore any late save for those IDs.
**Areas Addressed**: Storage, UI, UX
**Tests Added**: `Sources/MyNotes/SelfTest.swift` simulates a delayed editor save after deletion and confirms the text file stays absent.
**Boundary Validations**: Existing saves are still routed to the note's owning folder; a save after deletion cannot recreate the file.
**HITL Required**: Yes — delete the selected note in Quick Notes, close or switch the editor immediately, and verify the file remains deleted after reopening the folder.
**Regression Risk**: Low — only IDs whose delete operation succeeded are blocked from further saves.

## 2026-11-12 — Delete targets the note's actual folder

**Bug ID**: MYNOTES-NOTE-DELETE-OWNERSHIP
**Description**: Deleting a note during or just after a Notes Folder switch could fail because the note and the active folder store no longer referred to the same directory.
**Root Cause**: Deletion was routed through the currently selected `TextNoteStore`, even when the note's file belonged to a different folder.
**Fix Applied**: Delete through `TextNoteStore.owning(note:)`, which derives the store from the note's `.txt` file URL, and keep late saves from recreating a successfully deleted note.
**Areas Addressed**: Storage, UI
**Tests Added**: `Tests/MyNotesKitTests/TextNoteStoreTests.swift` verifies deletion after folder selection changes.
**Boundary Validations**: The note file is removed from its original folder; a different selected folder remains unchanged.
**HITL Required**: Yes — delete an existing note after changing folders and confirm only that note is removed.
**Regression Risk**: Low — deletion is confined to the exact file URL carried by the selected note.

## 2026-11-12 — Install current plain-text notes build

**Bug ID**: MYNOTES-STALE-INSTALLED-BUILD
**Description**: The installed app did not show the selected folder's existing `.txt` notes and reported an obsolete selected-folder save error.
**Root Cause**: The installed bundle was still build `202611120715`, while the source already included top-level `.txt` loading and owner-aware save/delete fixes.
**Fix Applied**: Rebuild and replace only `~/Applications/MyNotes.app`; preserve the chosen folder, every existing note, the clipboard preference, and clipboard history data.
**Areas Addressed**: Packaging, Storage
**Tests Added**: Existing plain-text store tests cover loading, saving, renaming, and deleting ordinary top-level `.txt` files.
**Boundary Validations**: Verified the chosen folder path and that it contains 99 top-level `.txt` files using file metadata only; note contents were not read.
**HITL Required**: Yes — open MyNotes and confirm the 99 notes appear and a new note saves in the selected folder.
**Regression Risk**: Low — installation replaces only the application bundle and does not migrate or rewrite note or clipboard data.
