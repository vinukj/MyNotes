# Bug fixes

## 2026-11-16 — Note-list text cannot be selected

**Bug ID**: MYNOTES-NOTE-TEXT-SELECTION
**Description**: Text shown in note-list rows could not be selected to use the system text actions.
**Root Cause**: The list labels did not enable text selection; the main list's custom context menu also took precedence over text actions.
**Fix Applied**: Enabled native text selection for note titles and body previews in both note lists and removed the row-level custom menus that intercepted the system context menu.
**Areas Addressed**: UI, UX
**Tests Added**: None; this uses SwiftUI's native selection and context-menu behavior.
**Boundary Validations**: List previews remain read-only; the editable body continues to use the note's debounced save path.
**HITL Required**: Yes — drag-select text in both lists and use the system context menu to copy it.
**Regression Risk**: Low — text-selection gestures may take precedence over row selection when dragging directly across labels.

## 2026-11-16 — Copy action missing from note text selection

**Bug ID**: MYNOTES-SELECTION-COPY-ACTION
**Description**: Selecting text in an editable note body did not provide an obvious, reliably clickable Copy action.
**Root Cause**: SwiftUI's `TextEditor` did not expose the selected range to the app; the first AppKit implementation placed its button relative to the selected line and fell back below it when there was no room above.
**Fix Applied**: Kept the AppKit text view and selection detection, and moved the bold Copy button into the top-left of the note-editor header whenever a non-empty selection exists. This keeps it clear of selected text and provides “Copied” feedback after writing the selection to the clipboard.
**Areas Addressed**: UI, UX
**Tests Added**: None; the existing suite and app build pass.
**Boundary Validations**: Clipboard is only changed after an explicit Copy click; existing note save handling remains in place.
**HITL Required**: Yes — visually verify the button appears at the editor's top-left, click it, and confirm “Copied” feedback and clipboard contents.
**Regression Risk**: Low — editor presentation is now hosted by `NSScrollView`/`NSTextView` instead of SwiftUI `TextEditor`.

## 2026-11-17 — OpenClip selection bar not summoned by MyNotes

**Bug ID**: MYNOTES-OPENCLIP-SELECTION-BAR
**Description**: The user expected OpenClip's action bar to appear as soon as text was selected in a note.
**Root Cause**: Not established. OpenClip's documented `openclip://` API has no command to show its selection bar or pass it selected text, but that does not explain why OpenClip's own automatic detection did not visibly present the bar.
**Fix Applied**: Kept MyNotes' own top-left Copy action as the supported fallback. No undocumented URL, synthetic shortcut, or OpenClip setting change was added.
**Areas Addressed**: UI, UX, integration boundary
**Tests Added**: None; a real mouse drag in the packaged synthetic verification app confirmed the selected text and MyNotes' top-left Copy button appear and that clicking it updates the button to “Copied.” OpenClip logs show it retrieved the selection from MyNotes, but do not establish whether its action bar was presented.
**Boundary Validations**: OpenClip reported no per-app rules; its documented command list contains only open-settings, pause, and resume, and the log has no “presentation blocked” entry for the observed selections. Verification used synthetic note data, not the user's notes. The installed MyNotes app signature is valid and its binary contains the selection-copy implementation.
**HITL Required**: Yes — verify OpenClip's automatic selection monitor in the user's real note and inspect OpenClip's own diagnostics if its bar still does not appear.
**Regression Risk**: Low — no OpenClip integration code or user configuration was changed; MyNotes' independent Copy action remains available. The cause of OpenClip's missing visible bar is unresolved.

## 2026-11-16 — Quick Notes editor hides the selected note body

**Bug ID**: MYNOTES-QUICK-NOTES-EDITOR-BODY
**Description**: Quick Notes showed the selected note's title but not its body in the editor.
**Root Cause**: The editor's `NSTextView` had no connected text storage/layout/container stack; attaching it to the scroll view discarded its initial string.
**Fix Applied**: Connected an explicit AppKit text system before attaching the editor, then populated the string after attachment.
**Areas Addressed**: UI
**Tests Added**: None; verified with seeded synthetic notes in the packaged app.
**Boundary Validations**: The test used a fresh `/tmp` note store; the user's notes were not used or changed.
**HITL Required**: No — editor body visibility was confirmed in a synthetic app screenshot.
**Regression Risk**: Low — note text binding and save behavior are unchanged.

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
