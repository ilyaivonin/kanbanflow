# Hamster's Kanban
<div align="center">

  <img src="https://github.com/user-attachments/assets/2c920851-5e5f-48d6-8228-86e9162010af" alt="Hamster's Kanban Logo" width="180">

  <h2>A native Kanban board for macOS.</h2>

  <p>Simple, lightweight, and entirely self-contained.</p>

  <p>
    <a href="https://github.com/ilyaivonin/hamsterskanban/releases/latest">
      <img src="https://img.shields.io/github/v/release/ilyaivonin/hamsterskanban?display_name=tag&style=for-the-badge" alt="Latest Release">
    </a>
    <a href="https://github.com/ilyaivonin/hamsterskanban/blob/main/LICENSE">
      <img src="https://img.shields.io/github/license/ilyaivonin/hamsterskanban?style=for-the-badge" alt="License">
    </a>
    <img src="https://img.shields.io/badge/macOS-12%2B-black?style=for-the-badge&logo=apple" alt="macOS 12+">
    <img src="https://img.shields.io/badge/Swift-AppKit-orange?style=for-the-badge&logo=swift" alt="Swift + AppKit">
    <img src="https://img.shields.io/badge/SQLite-Database-blue?style=for-the-badge&logo=sqlite" alt="SQLite">
  </p>

  <br>

  <a href="https://github.com/ilyaivonin/hamsterskanban/releases/latest">
    <img src="https://img.shields.io/badge/DOWNLOAD-RELEASE%201.0-2ea44f?style=for-the-badge" alt="Download Release 1.0">
  </a>

  <br><br>

  <sub>Built with Swift · AppKit · WKWebView · SQLite</sub>

</div>

---
**English version:** [README.md](README.md) · **Build instructions:** [BUILD.md](BUILD.md)

<div align="center">
  <img width="49%" alt="Screenshot 1" src="https://github.com/user-attachments/assets/fea6941f-310f-49c0-9a28-9d96bb1ba412" />
  <img width="49%" alt="Screenshot 2" src="https://github.com/user-attachments/assets/4ff048d3-8e70-49e6-b12e-0c5e100696c4" />
  <img width="49%" alt="Screenshot 3" src="https://github.com/user-attachments/assets/02829863-2d29-4f5b-8387-40252594f335" />
  <img width="49%" alt="Screenshot 4" src="https://github.com/user-attachments/assets/89dc50ee-cd55-479d-87ea-24bcb67189fa" />
  <img width="49%" alt="Screenshot 5" src="https://github.com/user-attachments/assets/ae653fa8-8df1-4842-97fc-7953ab5612c4" />
</div>

## Architecture

Hamster's Kanban is a hybrid macOS application.

- **`kanban.html` — User interface.** The board, modal windows, themes, and all interaction logic are written in HTML, CSS, and JavaScript and rendered through `WKWebView`.
- **`macos/main.swift` — Native wrapper.** AppKit creates the application window and menu bar, `WKWebView` displays the HTML interface, and native code handles SQLite, JSON file dialogs, backups, and the window title.

JavaScript and SQLite communicate through a lightweight `WKScriptMessageHandler` bridge (`window.webkit.messageHandlers.kanbanDB`). Whenever data is saved, the interface sends the complete application state as JSON. The native layer stores it in `app_state` and rebuilds the normalized database tables.

If the same `kanban.html` file is opened directly in a browser, the bridge is unavailable and the page uses `localStorage` instead.

## Features

- **Undo actions** — The **Undo** button in the header or `Cmd+Z` reverses the most recent change. History is stored in memory and supports up to 50 steps per session.
- **Multiple boards** with a dropdown switcher, board creation, and deletion.
- **Columns and cards** with drag-and-drop between columns, colored labeled separators, tags, priorities, assignees, descriptions, and subtasks.
- **Column management** — Duplicate a column (with all its cards) using the copy icon in its header, and drag columns by their header to reorder them. The order is saved to the database. Columns can also be dropped on either side of a date divider (left half = before the line, right half = after it), and a divider can be added after the last column using the "+" handle before "+ Add Column".
- **Finish button** — Every card has a checkmark button. On first use you choose one or more completion columns (for example Done), then pick where to move the card. Later presses offer only the previously chosen columns. The choice can be changed in Settings. Completed cards show a green checkmark on the board, in Projects, and in the calendar.
- **Click a calendar day** to create a new task with that date prefilled.
- **No duplicate calendar entries** — Cards with the same title, description and duration are shown only once per day, even if several such cards exist or the task spans multiple days.
- **Date ranges** — A start date and an optional end date. Overdue status is determined by the end date. The calendar displays every day within the range, and dragging a card preserves its duration.
- **Three views** — Board, calendar, and project tiles.
- **Search and filters** by tag, priority, and assignee.
- **Four themes** — Dark, light, blue, and green.
- **Application renaming** in settings. The name appears in the header, macOS window title, and exported backups.
- **Real SQLite database** — An authoritative JSON snapshot plus normalized tables for boards, columns, cards, separators, and settings.
- **Backups and data portability** — Full JSON backup and restore through native macOS dialogs, as well as individual board export and import.
- **Browser support** — When `kanban.html` is opened directly, the application uses `localStorage` and does not require the native wrapper.

## Requirements

- macOS 12 Monterey or later.
- Xcode Command Line Tools (Swift compiler and macOS SDK):

  ```bash
  xcode-select --install
  swiftc --version
  ```

Electron, Node.js, package managers, and third-party runtimes are not required.

## Quick Start

```bash
git clone https://github.com/ilyaivonin/hamsterskanban
cd hamsterskanban
./macos/build.sh
open dist/Hamster's Kanban.app
```

The build creates `dist/Hamster's Kanban.app`. You can move the application to `/Applications` to make it available in Launchpad.

For detailed build instructions, code signing, icons, and troubleshooting, see [BUILD.md](BUILD.md).

## Project Structure

```text
.
├── kanban.html              # Application interface, styles, and logic
├── macos/
│   ├── main.swift           # macOS wrapper, SQLite layer, and WebKit bridge
│   ├── Info.plist           # App bundle metadata
│   ├── build.sh             # Builds dist/Hamster's Kanban.app
│   └── make-icon.sh         # Recreates assets/AppIcon.icns
├── assets/
│   ├── icon.png             # Icon source (square PNG)
│   └── AppIcon.icns         # Icon used during the build
├── README.md                # English README
├── README.ru.md             # Russian README
├── BUILD.md                 # Detailed build instructions (EN)
├── BUILD.ru.md              # Detailed build instructions (RU)
└── .gitignore
```

## Data and Backups

The native application stores all data in:

```text
~/Library/Application Support/Hamster's Kanban/hamsterskanban.sqlite
```

Database structure:

| Table | Purpose |
| --- | --- |
| `app_state` | Authoritative JSON snapshot loaded by the interface |
| `boards`, `columns`, `cards`, `separators` | Normalized representation of the same data |
| `settings` | Application name, completion columns, and other key-value settings |
| `backups` | The last 20 snapshots created during export/import operations |

**Settings → Reveal Database** opens the database location in Finder. The same section also displays the number of records and the database file size.

### Full Backup and Individual Boards

- **Export Full Backup (JSON)** saves all boards, cards, separators, theme, ordering, completion columns, and application name.
- **Import Backup (JSON)** replaces the database contents with data from the selected file. Before replacement, the current state is saved to the `backups` table.
- **Export Current Board** saves a single board.
- **Import Board** adds a board from a file and switches to it.

On macOS, `Cmd+Shift+E` opens the full backup export dialog, while `Cmd+Shift+I` opens the import dialog.

## Keyboard Shortcuts

The in-app help displays `Ctrl` shortcuts; the same combinations work with `Cmd` on macOS.

| Shortcut | Action |
| --- | --- |
| `Cmd/Ctrl + Z` | Undo the last action |
| `Cmd/Ctrl + N` | Create a new card |
| `Cmd/Ctrl + B` | Create a new board |
| `Cmd/Ctrl + E` | Export the current board |
| `Cmd/Ctrl + T` | Switch theme |
| `Cmd/Ctrl + K` | Open keyboard shortcuts help |
| `Cmd/Ctrl + ,` | Open settings |
| `/` | Focus the search field |
| `Esc` | Close a modal window or board menu |
| `1`–`9` | Navigate to a column |
| `Cmd+Shift+E` | Export full backup (macOS menu) |
| `Cmd+Shift+I` | Import backup (macOS menu) |

## Development

The interface is plain HTML/CSS/JavaScript in `kanban.html`; there is no separate frontend build process.

After making changes, rebuild the application to include the updated HTML in the bundle:

```bash
./macos/build.sh
open dist/Hamster's Kanban.app
```

To run the application with a temporary database without touching your actual data:

```bash
KANBANFLOW_DB_PATH=/tmp/hamsterskanban-dev.sqlite \
  ./dist/Hamster's Kanban.app/Contents/MacOS/Hamster's Kanban
```

The native binary also includes a database self-test:

```bash
./dist/Hamster's Kanban.app/Contents/MacOS/Hamster's Kanban --selftest
```

## Application Icon

The icon source is `assets/icon.png`, which must be a square PNG.

After replacing the image, regenerate the `.icns` file:

```bash
./macos/make-icon.sh assets/icon.png
./macos/build.sh
```

## License

Released under the MIT License. See `LICENSE`.

## Troubleshooting

| Problem | Solution |
| --- | --- |
| `swiftc: command not found` | Run `xcode-select --install` and try building again. |
| macOS won't open the application | Right-click the application and select **Open**, or allow it under **System Settings → Privacy & Security**. |
| The old icon is still displayed | Move the application or run `touch dist/Hamster's Kanban.app`. Finder caches application icons. |
| Changes to `kanban.html` are not visible | Rebuild using `./macos/build.sh` — the HTML file is copied into the application bundle. |
| A clean database is needed | Close the application and move `~/Library/Application Support/Hamster's Kanban/hamsterskanban.sqlite` somewhere else. |
