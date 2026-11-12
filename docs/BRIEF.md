# MyNotes

A calm, local-first Mac notes app for capturing a thought from anywhere and finding it again quickly. Notes are ordinary `.txt` files in the selected folder; optional richer clipboard history has a separate local database.

## Replaces
Unclutter-style quick notes and the user's scattered scratch notes.

## Main jobs
1. Reveal quick notes by moving the pointer to the top edge and scrolling down.
2. Create and edit notes in the quick panel or full library.
3. Search note titles and contents, and browse every note.

## Data
- Note: stable ID, title, body, created date, edited date.

## Shape
A regular macOS app with a searchable library window and a floating quick-notes panel. macOS 26 or later. Offline, local data, no account or server. The notes folder can be changed in Settings.

## System hooks
Global mouse-move and scroll-wheel monitors for the required top-edge gesture. No keyboard, Accessibility, or Screen Recording permission. A menu command and shortcut provide a fallback to reveal the panel.

## Reference
Unclutter, for the top-edge reveal interaction and quick-access feel.

## Look
Native macOS controls and system appearance, with a compact floating panel and minimal custom chrome.

## Not in version one
- Cloud sync, accounts, collaboration, attachments, tags, and rich-text formatting.
- Launch-at-login, global hotkey customization, and menu-bar extra.

## Design plan
- Archetype: sidebar library window plus a floating quick-notes panel.
- Information architecture: All Notes; the panel shows the same notes in a compact searchable surface.
- Command map: New Note (Command-N); Show Quick Notes (Command-Shift-N); Search (Command-F); Settings (Command-comma); standard Delete for the selected note.
- Empty states: invite the user to create their first note; the panel offers New Note when empty.
- Feeling: calm and immediate, with the note content kept visually dominant.
