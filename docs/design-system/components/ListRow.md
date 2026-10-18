# List row

One row for folders in the browser and tracks in the queue. The unit of all navigation.

## Anatomy
A 12px column (`folder` icon for folders, LED for tracks) · name in `body` · on the right, duration in `duration` or the folder's contents in `caption`.

## States
- Rest: transparent background. No dividers between rows.
- Hover: `surface-1` background, corners `radius-sm`.
- Selected: `surface-2` background, corners `radius-sm`.
- Playing: `led` lit in the left column and the name in `signal`. The only place the accent appears in a list.

## Rules
- Fixed height `row` (28px), horizontal padding `space-2`.
- No queue position number: the file already carries its own.
- The name is the file name without extension (the format is on the display) or the folder name, with no tag clean-up. Truncate at the end; tooltip with the full name, extension included.
- Double-click or Enter plays; ⌘Enter adds to the queue; drag reorders the queue.
