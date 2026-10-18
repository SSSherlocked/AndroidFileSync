# Release Notes

This file records the changes in each release of [SSSherlocked/AndroidFileSync](https://github.com/SSSherlocked/AndroidFileSync), starting with the first release published from this repository. Each version has an `# AndroidFileSync v<version>` heading and ends with a line containing only `---`. The Build Release workflow publishes a version's section as its release description.

Earlier history belongs to the original project: [Santosh7017/AndroidFileSync](https://github.com/Santosh7017/AndroidFileSync).

# AndroidFileSync v2.3.7

## 👥 Multiple users

- **Switch between Android users**: when the phone has more than one user (owner, app clone space, second space…), a user menu appears at the top of the sidebar. Choosing a user shows that user's storage; Quick Access's default folders, the Go menu and `~` in Go to Folder follow it. On connect, the phone's current user is selected.
- **Every user is tested first**: some phones block other users' storage. Before a user can be chosen, the app checks that its folders can really be opened and whether files can be written. Blocked users are listed with the reason and can't be chosen; users whose files are blocked but whose media library is readable are marked "media library only" (not browsable yet).

## 📌 Sidebar

- **Pin a folder by dragging it to the sidebar**: drag a folder from the file list between the Quick Access folders, or onto the new "Drop folders here to pin" strip at the bottom of the sidebar, which highlights while you hover. You can still pin a folder by right-clicking it and choosing Add to Sidebar.
- **No more freeze when dropping folders on the sidebar**: dropping a folder anywhere on the sidebar used to hang the app, so it had to be force quit. A drop now only reads where the folder is on the phone, never its contents, so it can't hang.
- **Quick Access folders no longer go missing**: if the app opened before the phone was fully connected, some sidebar folders could disappear until another folder was added. Folders are now hidden only when the phone confirms they don't exist, and the sidebar is checked again as soon as the phone connects.
- **Pinning a folder that is already in the sidebar** shows it again if it had been hidden by mistake, instead of doing nothing.

## 🖱 Drag and drop

- **Text files can be dragged to Finder**: .txt, .log, .json and other text files used to be refused when dropped in Finder. They now download like any other file.
- **Starting a drag no longer stalls**: cleaning up old temporary files left by earlier drags now happens in the background instead of blocking the window.

## 📄 Opening files

- **Double-click opens a file in its Mac app**, as in Finder: the file is downloaded to a temporary folder and opened with its default app. If no app on the Mac can open it, you're asked where to save it instead. File › Open (⌘↓) does the same; Space still shows the preview.
- **Text files show their contents in the preview**: txt, log, md, json, csv and source code files show their text (the first 512 KB) instead of only an icon.

---

# AndroidFileSync v2.3.6

## 🖱 Drag and drop

- **Dragging files to Finder copies the real file again**: in 2.3.5, a file dragged to Finder could arrive as a one-line file containing its path on the phone instead of its contents. Files you dragged out with 2.3.5 should be dragged again.

## ⚙️ App

- **Quitting no longer hangs**: Command-Q could freeze while the app disconnected from the phone. Disconnecting on quit now gives up after a couple of seconds.

---

# AndroidFileSync v2.3.5

## 🗂 Finder-style menus and windows

- **Menu bar commands**: new File, View and Go menus, plus Deselect All (⌥⌘A) in the Edit menu. Every file action is listed with its keyboard shortcut.
- **Settings window (⌘,)**: default view, hidden files, status bar, preview pane, disconnecting wireless devices on quit, the quit reminder and diagnostic logging.
- **Go to Folder (⌘⇧G)**: type a path to jump to it, with folder suggestions as you type and Tab to complete. `~` is internal storage; paths without a leading `/` are relative to the current folder.
- **Status bar (⌘/)**: shows the number of items, how many are selected and the free space on the phone.
- **Back and Forward buttons** in the toolbar, and every part of the path bar is clickable. The middle of a long path opens from a "…" menu.
- **Hidden files**: files whose names start with a dot are hidden by default, as in Finder. Show them with ⌘⇧. or in Settings.

## 🖼 Browsing

- **Icon view (⌘2)**: thumbnails in a grid. Click, ⌘-click and ⇧-click to select, double-click to open, click empty space to deselect. ⌘1 returns to the list.
- **Preview pane (⌘⇧P)**: a large preview and details of the selected file on the right. With several items selected it shows how many and their total size.
- **Type to select**: type the start of a name to jump to that item.

## 🖱 Drag and drop

- **Move files by dragging** them onto a folder in the list or icon view. Name conflicts are handled as with paste, and the clipboard is left alone.
- **Upload into a folder** by dragging files from Finder onto it.

---

# AndroidFileSync v2.3.4

## 📶 Wireless connection

- **First-time QR pairing works**: on macOS 15 and later, the first QR scan used to fail while macOS asked for Local Network permission. The app now asks as soon as the WiFi window opens, keeps the QR code valid while you decide, and finishes pairing on its own once access is allowed, with no need to scan again. A notice with a shortcut to Local Network settings appears while access is blocked.
- **More reliable connection after pairing**: connecting right after pairing is retried a few times instead of failing on the first try.

## 📌 Sidebar

- **Trash menu**: right-click Trash in the sidebar to open it, restore everything or empty it.
- **Restore Hidden Folders** moved into the right-click menu of the Quick Access folders.

---

# AndroidFileSync v2.3.3

## 🗂 Finder-style toolbar

- **File actions in the toolbar**: Copy, Cut, Paste, Move to Trash and an Action menu (Rename, Get Info, Quick Look, Download, Upload, Select All, Delete Immediately).
- **Customizable toolbar**: hold Command and drag buttons to rearrange them, or right-click the toolbar and choose Customize Toolbar…

## 📌 Sidebar

- **Reorder Quick Access folders** by dragging them.
- **Edit a sidebar folder** (name, icon and color) from its right-click menu.
- **Aligned icons**: all sidebar labels now start at the same indent.

## 🖱 Drag and drop

- **Drag files and folders to Finder** to download them. The download starts when you drop, with progress in the transfer panel.

## 🎨 Look

- **Full-size app icon**: the icon now matches the size of other macOS app icons.

## 🧹 Removed

- The report-issue button and popover, the periodic "Star on GitHub" prompt and the GitHub link at the bottom of the sidebar.

---
