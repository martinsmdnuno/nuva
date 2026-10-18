# Text button

The same key with a label, for actions outside playback: add folder, play folder, try again.

## Rules
- Face `key-mode`, `label` text in `key-mode-ink`, height `key-text` (28px), horizontal padding `space-3`, corners `radius-sm`. No outline.
- Never amber: amber belongs to the play key only. A dialog's main action stands out by position (on the right).
- Verb-first label, no full stop: "Add Folder", "Try Again".
- The caller provides the label and the action.
