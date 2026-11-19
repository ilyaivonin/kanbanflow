# Building KanbanFlow

This guide covers building, running, and troubleshooting the KanbanFlow macOS application.

**English version:** [BUILD.md](BUILD.md)

---

## 1. Requirements

- macOS 12 Monterey or later.
- Xcode Command Line Tools. A full Xcode installation is not required.
- No internet connection is required during the build process.

Install the tools once:

```bash
xcode-select --install
```

Check the compiler:

```bash
swiftc --version
```

You should see the Apple Swift version. If you encounter the error `xcrun: error: unable to find utility clang`, run:

```bash
sudo xcode-select --switch /Library/Developer/CommandLineTools
```

## 2. Getting the Source Code

```bash
git clone https://github.com/ilyaivonin/kanbanflow
cd kanbanflow
```

If you downloaded a ZIP archive, extract it and open the project folder in Terminal.

## 3. Building the Application

From the repository root:

```bash
chmod +x macos/build.sh macos/make-icon.sh
./macos/build.sh
```

The script:

1. Compiles `macos/main.swift` using `swiftc`.
2. Creates `dist/KanbanFlow.app`.
3. Copies `kanban.html`, `Info.plist`, and `assets/AppIcon.icns` into the application bundle.
4. Applies an ad-hoc signature sufficient for local execution.

Expected output:

```text
Compiling native shell for arm64...
Built: /path/to/kanbanflow/dist/KanbanFlow.app
Run:   open "/path/to/kanbanflow/dist/KanbanFlow.app"
```

The architecture is detected automatically using `uname -m`. To explicitly build for a specific architecture:

```bash
KANBANFLOW_ARCH=x86_64 ./macos/build.sh
# or
KANBANFLOW_ARCH=arm64 ./macos/build.sh
```

The script builds for only one architecture at a time. To create a universal binary, you must build both versions and combine them using `lipo`. This is not automated.

## 4. Running the Application

```bash
open dist/KanbanFlow.app
```

Alternatively, double-click `dist/KanbanFlow.app` in Finder. To make the application available in Launchpad, move it to `/Applications`.

On the first launch, macOS automatically creates the database:

```text
~/Library/Application Support/KanbanFlow/kanbanflow.sqlite
```

Rebuilding the application does not modify your existing data.

## 5. Verifying the Build

Run the built-in database self-test:

```bash
./dist/KanbanFlow.app/Contents/MacOS/KanbanFlow --selftest
```

It uses a temporary SQLite file, verifies the normalized tables, and prints a JSON report:

```json
{
  "appName": "Self Test",
  "backupRecorded": true,
  "boards": 1,
  "cards": 1,
  "columns": 2,
  "loadedMatches": true,
  "separators": 1
}
```

To run the application with a separate database (useful for testing):

```bash
KANBANFLOW_DB_PATH=/tmp/kanbanflow-test.sqlite \
  ./dist/KanbanFlow.app/Contents/MacOS/KanbanFlow
```

Your primary database remains untouched.

## 6. Rebuilding After Changes

The main project files are:

- `kanban.html` — application interface and logic.
- `macos/main.swift` — native wrapper, SQLite schema, and WebKit bridge.
- `macos/Info.plist` — application bundle metadata and version.
- `assets/icon.png` — icon source image.

After making changes, rebuild the application:

```bash
./macos/build.sh
open dist/KanbanFlow.app
```

There is no separate frontend build process. The HTML file is copied directly into the application bundle.

If you modify `kanban.html` without rebuilding the application, it will continue using the old copy inside the bundle.

## 7. Regenerating the Application Icon

`assets/AppIcon.icns` is already included in the repository, so a normal build does not need to regenerate it.

After replacing `assets/icon.png` (square PNG, preferably 1024×1024):

```bash
./macos/make-icon.sh assets/icon.png
./macos/build.sh
```

The script checks that the image is square, generates all required iconset sizes, and runs `iconutil`.

If Finder continues displaying the old icon, move the application to another folder or run:

```bash
touch dist/KanbanFlow.app
```

macOS aggressively caches application icons.

## 8. Code Signing and Distribution

`build.sh` applies an **ad-hoc** signature (`codesign --sign -`). This is sufficient for running the application on the machine where it was built.

To distribute the application to other users, a Developer ID signature is required.

If Gatekeeper blocks a downloaded application:

- Right-click the application → **Open** → **Open**; or
- Allow it under **System Settings → Privacy & Security** → **Open Anyway**; or
- Remove the quarantine attribute:

  ```bash
  xattr -dr com.apple.quarantine /path/to/KanbanFlow.app
  ```

## 9. Changing the Bundle Identifier

Before publishing a fork, update:

- `CFBundleIdentifier` in `macos/Info.plist` (for example, `com.example.kanbanflow`).
- `CFBundleName` / `CFBundleDisplayName` if you want a different bundle name.
- `APP_NAME` in `macos/build.sh` if the executable filename should change.

The visible application name can be changed at runtime in **Settings**. This affects the header, window title, and backups, but does not change the bundle identifier.

## 10. Data, Backups, and Resetting

Primary database:

```text
~/Library/Application Support/KanbanFlow/kanbanflow.sqlite
```

To start with a clean database while preserving your existing data:

```bash
# Close KanbanFlow first
mv "$HOME/Library/Application Support/KanbanFlow" \
   "$HOME/Library/Application Support/KanbanFlow.backup"
open dist/KanbanFlow.app
```

To permanently delete all application data:

```bash
rm -rf "$HOME/Library/Application Support/KanbanFlow"
```

Before deleting anything, use **Settings → Backup to File**.

The `backups` table stores the last 20 snapshots created during export/import operations, but these snapshots are stored in the same database file.

## 11. Troubleshooting

| Symptom | Cause / Solution |
| --- | --- |
| `swiftc: command not found` | Install Xcode Command Line Tools: `xcode-select --install` |
| `xcrun: error: unable to find utility clang` | Set the CLT directory: `sudo xcode-select --switch /Library/Developer/CommandLineTools` |
| Build fails on an older macOS version | The build target is macOS 12.0. Update macOS or modify `-target` in `macos/build.sh`. |
| Application opens with a blank window | Check the project structure: `kanban.html` must be in the repository root and copied by `build.sh`. |
| Interface changes are not visible | Rebuild using `./macos/build.sh`. |
| Window title does not change after renaming | Use **Settings** in the application (or `Cmd+,`). The title is updated through the native bridge. |
| `database is locked` | Close all KanbanFlow instances and reopen the application. |
| Build and runtime logs are needed | Launch the binary directly from Terminal: `./dist/KanbanFlow.app/Contents/MacOS/KanbanFlow` |

## 12. Build Output

The build process creates the following structure:

```text
dist/
└── KanbanFlow.app/
    └── Contents/
        ├── Info.plist
        ├── MacOS/KanbanFlow
        ├── PkgInfo
        ├── Resources/kanban.html
        └── Resources/AppIcon.icns
```