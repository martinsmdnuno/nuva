# Player window

How the pieces come together in the "Player with queue" size (360 × 480 or taller). The reference for assembly.

## Structure
Everything sits on the `surface-0` chassis, margin `space-4`. No cards.
1. Display at the top, with the position bar inside.
2. `space-4` · Keys in three groups with legends: playback on the left, mode in the middle, output on the right, spread across the full width.
3. `space-3` · Volume: the "volume" legend and a bar with a 0–10 scale.
4. `space-4` · Queue: header with the folders key on the left and the "queue 11 tracks · 39:18" legend on the right, then the rows down to the bottom.

## Compact (⌘3)
Steps 1 to 3 and the queue header, without rows. The window takes the height of its content. The header stays so someone new to the app can see the way back.

## Folders key
Someone new to the app must see that there is a drawer, and how to open and close it. In the queue header, on the left (the side the drawer opens from): a mode key with `sidebar.left`, an LED above it (on while the drawer is open) and the legend "folders" next to it.
- Clicking opens or closes the drawer, like ⌘B. Tooltip "Show folders ⌘B" / "Hide folders ⌘B".
- Always there, also with an empty queue and in compact mode.
- With the drawer open, the browser header has the same key in its right corner, next to the divider, to close it.

## Queue legend
On the right of the same header: LED + "queue" in `legend` + total in 10px mono. LED on while the queue is visible. Clicking switches between player and compact (⌘1 / ⌘3).

## Rules
- Nothing above the display except the native macOS title bar.
- The queue shows the current folder by default. Adding another folder appends it.
- In the browser size (720 × 480 or taller), the folder browser comes in on the left, on the same plane, separated by a vertical `line` divider.

## First launch and empty queue
- **No sources:** the display says "No music · Add a folder or a Jellyfin server". In place of the queue, the legend "get started" and the two ways to bring in music, each with a text button, one line saying what it is, and its shortcut: "Add Folder" (music on this Mac or a network drive, ⌘O) and "Add Jellyfin" (a Jellyfin server, with your account, ⇧⌘O).
- **Sources, empty queue:** "Queue is empty · Open the folders and play one" and a "Show Folders" button (⌘B).
- Play with an empty queue opens the folders.
