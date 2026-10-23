# Player window

How the pieces come together, 360 to 640 wide and 540 or taller. The reference for assembly.

## Structure
Everything sits on the `surface-0` chassis, margin `space-4`. No cards.
1. Display at the top, with the position bar inside.
2. `space-4` · Keys in three groups with legends: playback on the left, mode in the middle, output on the right, spread across the full width.
3. `space-3` · Volume: the "volume" legend and a bar with a 0–10 scale.
4. `space-4` · Queue or folders: a header row, then the rows down to the bottom.

## Compact (⌘3)
Steps 1 to 3 and the queue header, without rows. The window takes the height of its content. The header stays so someone new to the app can see the way back.

## Header row
The same row in every mode, so the way to the folders and back is always in the same place.
- **Folders key** on the left: a mode key with `sidebar.left`, an LED above it (on while the folders show). Clicking swaps queue and folders, like ⌘B. Tooltip "Show folders ⌘B" / "Show queue ⌘B". Always there, also with an empty queue and in compact mode.
- **With the queue** (and in compact): the legend "folders" next to the key and, on the right, LED + "queue" in `legend` + total in 10px mono. The queue LED is on while the queue shows; clicking it switches between queue and compact (⌘1 / ⌘3).
- **With the folders**: the legends give way to the browser's keys, on the same row: up (`chevron.left`, ←), the source icon and the folder name in `label`, "Play Folder" on the right, and eject for a CD. The rows get all the room below.

## Rules
- Nothing above the display except the native macOS title bar.
- The queue shows the current folder by default. Adding another folder appends it.
- The folders replace the queue in place, with a 200ms cross-fade. Playing from them (Enter, double-click, Play Folder) brings the queue back; ⌘Enter adds to the queue and stays.
- Wider than 360, only the space grows: no key, LED or legend changes size.

## First launch and empty queue
- **No sources:** the display says "No music · Add a folder or a Jellyfin server". In place of the queue, the legend "get started" and the two ways to bring in music, each with a text button, one line saying what it is, and its shortcut: "Add Folder" (music on this Mac or a network drive, ⌘O) and "Add Jellyfin" (a Jellyfin server, with your account, ⇧⌘O).
- **Sources, empty queue:** "Queue is empty · Open the folders and play one" and a "Show Folders" button (⌘B).
- Play with an empty queue opens the folders.
