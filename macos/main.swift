import AppKit
import Foundation
import SQLite3
import UniformTypeIdentifiers
import WebKit

// The native shell around kanban.html. The web view owns the UI; this file
// provides the macOS window, the SQLite database and native file panels.

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Helpers

private func nowISO() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

private func jsLiteral(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value) else { return "null" }
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: []),
          var string = String(data: data, encoding: .utf8) else { return "null" }
    string = string.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
    string = string.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    return string
}

private func jsonStringLiteral(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
          let arrayLiteral = String(data: data, encoding: .utf8) else { return "null" }
    // ["..."] -> "..." so it can be passed as a single JS argument.
    return String(arrayLiteral.dropFirst().dropLast())
}

private func prettyJSONString(from object: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

// MARK: - SQLite database

final class KanbanDatabase {
    private var db: OpaquePointer?
    let path: String

    init(path overridePath: String? = nil) {
        let fileManager = FileManager.default
        let resolvedPath: String

        if let overridePath, !overridePath.isEmpty {
            resolvedPath = overridePath
        } else if let envPath = ProcessInfo.processInfo.environment["KANBANFLOW_DB_PATH"], !envPath.isEmpty {
            resolvedPath = envPath
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = support.appendingPathComponent("KanbanFlow", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            resolvedPath = directory.appendingPathComponent("kanbanflow.sqlite").path
        }

        path = resolvedPath
        let parent = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent()
        try? fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        if sqlite3_open(resolvedPath, &db) != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            print("Hamster's Kanban: cannot open database at \(resolvedPath): \(message)")
        }

        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA foreign_keys=ON;")
        exec("PRAGMA synchronous=NORMAL;")
        createSchema()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func errorMessage() -> String {
        guard let db else { return "database is closed" }
        return String(cString: sqlite3_errmsg(db))
    }

    @discardableResult
    func exec(_ sql: String) -> Bool {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            if let error {
                print("Hamster's Kanban SQL error: \(String(cString: error))")
                sqlite3_free(error)
            } else {
                print("Hamster's Kanban SQL error: \(errorMessage())")
            }
            return false
        }
        return true
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            print("Hamster's Kanban SQL prepare error: \(errorMessage()) for \(sql)")
            return nil
        }
        return statement
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindInt(_ statement: OpaquePointer?, _ index: Int32, _ value: Int) {
        sqlite3_bind_int64(statement, index, sqlite3_int64(value))
    }

    private func createSchema() {
        exec("""
        CREATE TABLE IF NOT EXISTS app_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            payload TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS boards (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            position INTEGER NOT NULL,
            column_order TEXT NOT NULL,
            last_modified TEXT
        );
        CREATE TABLE IF NOT EXISTS columns (
            id TEXT NOT NULL,
            board_id TEXT NOT NULL,
            title TEXT NOT NULL,
            position INTEGER NOT NULL,
            PRIMARY KEY (board_id, id)
        );
        CREATE TABLE IF NOT EXISTS cards (
            id TEXT NOT NULL,
            board_id TEXT NOT NULL,
            column_id TEXT NOT NULL,
            title TEXT,
            description TEXT,
            label TEXT,
            priority TEXT,
            due_date TEXT,
            due_date_end TEXT,
            assignee TEXT,
            avatar TEXT,
            subtasks INTEGER DEFAULT 0,
            subtasks_total INTEGER DEFAULT 0,
            created_at TEXT,
            position INTEGER NOT NULL,
            comments_json TEXT,
            activity_json TEXT,
            PRIMARY KEY (board_id, id)
        );
        CREATE TABLE IF NOT EXISTS separators (
            id TEXT NOT NULL,
            board_id TEXT NOT NULL,
            label TEXT,
            color TEXT,
            before_col TEXT,
            position INTEGER NOT NULL,
            PRIMARY KEY (board_id, id)
        );
        CREATE TABLE IF NOT EXISTS backups (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            payload TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_cards_board ON cards(board_id);
        CREATE INDEX IF NOT EXISTS idx_cards_column ON cards(board_id, column_id);
        CREATE INDEX IF NOT EXISTS idx_columns_board ON columns(board_id);
        """)
    }

    // MARK: Settings

    func appName() -> String {
        guard let statement = prepare("SELECT value FROM settings WHERE key = 'app_name' LIMIT 1;") else {
            return "Hamster's Kanban"
        }
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) {
            return String(cString: text)
        }
        return "Hamster's Kanban"
    }

    func setAppName(_ name: String) {
        guard let statement = prepare("INSERT INTO settings(key, value) VALUES('app_name', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;") else { return }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, name)
        sqlite3_step(statement)
    }

    // MARK: State

    func loadState() -> String? {
        guard let statement = prepare("SELECT payload FROM app_state WHERE id = 1 LIMIT 1;") else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: text)
    }

    func saveState(json: String) {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            print("Hamster's Kanban: refusing to save malformed state")
            return
        }

        exec("BEGIN IMMEDIATE TRANSACTION;")
        var success = true

        // Whole-state snapshot (the authoritative source for the web view).
        if let statement = prepare("""
            INSERT INTO app_state(id, payload, updated_at) VALUES(1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at;
            """) {
            bindText(statement, 1, json)
            bindText(statement, 2, nowISO())
            if sqlite3_step(statement) != SQLITE_DONE { success = false }
            sqlite3_finalize(statement)
        } else { success = false }

        if success {
            let appName = ((root["settings"] as? [String: Any])?["appName"] as? String)
                ?? (root["appName"] as? String)
                ?? "Hamster's Kanban"
            setAppName(appName)
        }

        // Normalized mirror of the same state, so the database is useful for
        // queries and external tools as well.
        if success {
            exec("DELETE FROM boards; DELETE FROM columns; DELETE FROM cards; DELETE FROM separators;")

            let boards = root["boards"] as? [String: Any] ?? [:]
            let boardOrder = root["boardOrder"] as? [String] ?? boards.keys.sorted()
            let globalColumnOrder = root["columnOrder"] as? [String] ?? []

            if let boardStatement = prepare("INSERT INTO boards(id, name, position, column_order, last_modified) VALUES(?, ?, ?, ?, ?);"),
               let columnStatement = prepare("INSERT INTO columns(id, board_id, title, position) VALUES(?, ?, ?, ?);"),
               let cardStatement = prepare("""
                    INSERT INTO cards(id, board_id, column_id, title, description, label, priority,
                                      due_date, due_date_end, assignee, avatar, subtasks, subtasks_total,
                                      created_at, position, comments_json, activity_json)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """),
               let separatorStatement = prepare("INSERT INTO separators(id, board_id, label, color, before_col, position) VALUES(?, ?, ?, ?, ?, ?);") {

                var boardPosition = 0
                var orderedBoardIDs = boardOrder.filter { boards[$0] != nil }
                for id in boards.keys where !orderedBoardIDs.contains(id) { orderedBoardIDs.append(id) }

                for boardID in orderedBoardIDs {
                    guard let board = boards[boardID] as? [String: Any] else { continue }
                    let boardName = (board["name"] as? String) ?? "Board"
                    let columns = board["columns"] as? [String: Any] ?? [:]
                    let columnOrder = globalColumnOrder.filter { columns[$0] != nil }

                    sqlite3_reset(boardStatement)
                    sqlite3_clear_bindings(boardStatement)
                    bindText(boardStatement, 1, boardID)
                    bindText(boardStatement, 2, boardName)
                    bindInt(boardStatement, 3, boardPosition)
                    bindText(boardStatement, 4, columnOrder.isEmpty ? columns.keys.sorted().joined(separator: ",") : columnOrder.joined(separator: ","))
                    bindText(boardStatement, 5, nowISO())
                    if sqlite3_step(boardStatement) != SQLITE_DONE { success = false }
                    boardPosition += 1

                    var columnPosition = 0
                    var orderedColumnIDs = columnOrder
                    for id in columns.keys where !orderedColumnIDs.contains(id) { orderedColumnIDs.append(id) }

                    for columnID in orderedColumnIDs {
                        guard let column = columns[columnID] as? [String: Any] else { continue }
                        sqlite3_reset(columnStatement)
                        sqlite3_clear_bindings(columnStatement)
                        bindText(columnStatement, 1, columnID)
                        bindText(columnStatement, 2, boardID)
                        bindText(columnStatement, 3, (column["title"] as? String) ?? "Column")
                        bindInt(columnStatement, 4, columnPosition)
                        if sqlite3_step(columnStatement) != SQLITE_DONE { success = false }
                        columnPosition += 1
                    }

                    let cardsByColumn = board["cards"] as? [String: Any] ?? [:]
                    for (columnID, rawCards) in cardsByColumn {
                        guard let cards = rawCards as? [Any] else { continue }
                        var cardPosition = 0
                        for rawCard in cards {
                            guard let card = rawCard as? [String: Any] else { continue }
                            sqlite3_reset(cardStatement)
                            sqlite3_clear_bindings(cardStatement)
                            bindText(cardStatement, 1, card["id"] as? String)
                            bindText(cardStatement, 2, boardID)
                            bindText(cardStatement, 3, columnID)
                            bindText(cardStatement, 4, card["title"] as? String)
                            bindText(cardStatement, 5, card["description"] as? String)
                            bindText(cardStatement, 6, card["label"] as? String)
                            bindText(cardStatement, 7, card["priority"] as? String)
                            bindText(cardStatement, 8, card["dueDate"] as? String)
                            bindText(cardStatement, 9, card["dueDateEnd"] as? String)
                            bindText(cardStatement, 10, card["assignee"] as? String)
                            bindText(cardStatement, 11, card["avatar"] as? String)
                            bindInt(cardStatement, 12, card["subtasks"] as? Int ?? 0)
                            bindInt(cardStatement, 13, card["subtasksTotal"] as? Int ?? 0)
                            bindText(cardStatement, 14, card["createdAt"] as? String)
                            bindInt(cardStatement, 15, cardPosition)
                            bindText(cardStatement, 16, prettyJSONCompact(card["comments"]))
                            bindText(cardStatement, 17, prettyJSONCompact(card["activity"]))
                            if sqlite3_step(cardStatement) != SQLITE_DONE { success = false }
                            cardPosition += 1
                        }
                    }

                    let separators = board["separators"] as? [Any] ?? []
                    var separatorPosition = 0
                    for rawSeparator in separators {
                        guard let separator = rawSeparator as? [String: Any] else { continue }
                        sqlite3_reset(separatorStatement)
                        sqlite3_clear_bindings(separatorStatement)
                        bindText(separatorStatement, 1, separator["id"] as? String)
                        bindText(separatorStatement, 2, boardID)
                        bindText(separatorStatement, 3, separator["label"] as? String)
                        bindText(separatorStatement, 4, separator["color"] as? String)
                        bindText(separatorStatement, 5, separator["before"] as? String)
                        bindInt(separatorStatement, 6, separatorPosition)
                        if sqlite3_step(separatorStatement) != SQLITE_DONE { success = false }
                        separatorPosition += 1
                    }
                }

                sqlite3_finalize(boardStatement)
                sqlite3_finalize(columnStatement)
                sqlite3_finalize(cardStatement)
                sqlite3_finalize(separatorStatement)
            } else {
                success = false
            }
        }

        if success {
            exec("COMMIT;")
        } else {
            exec("ROLLBACK;")
            print("Hamster's Kanban: database save failed, rolled back")
        }
    }

    private func prettyJSONCompact(_ value: Any?) -> String? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Backups

    func recordBackup(json: String) {
        if let statement = prepare("INSERT INTO backups(created_at, payload) VALUES(?, ?);") {
            bindText(statement, 1, nowISO())
            bindText(statement, 2, json)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        exec("DELETE FROM backups WHERE id NOT IN (SELECT id FROM backups ORDER BY id DESC LIMIT 20);")
    }

    func backupCount() -> Int {
        guard let statement = prepare("SELECT COUNT(*) FROM backups;") else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    // MARK: Info

    func stats() -> [String: Any] {
        func count(_ table: String) -> Int {
            guard let statement = prepare("SELECT COUNT(*) FROM \(table);") else { return 0 }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(statement, 0))
        }

        var size = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let number = attributes[.size] as? NSNumber {
            size = number.intValue
        }
        return [
            "native": true,
            "engine": "SQLite database",
            "path": path,
            "boards": count("boards"),
            "columns": count("columns"),
            "cards": count("cards"),
            "separators": count("separators"),
            "backups": backupCount(),
            "sizeBytes": size
        ]
    }
}

// MARK: - Native bridge

final class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    weak var window: NSWindow?
    let database: KanbanDatabase
    private(set) var appName: String

    init(database: KanbanDatabase) {
        self.database = database
        self.appName = database.appName()
        super.init()
    }

    func setWindow(_ window: NSWindow) {
        self.window = window
        window.title = appName
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        let payload = body["payload"]

        switch action {
        case "save":
            guard let state = payload as? [String: Any], let json = prettyJSONCompact(state) else {
                print("Hamster's Kanban: save ignored, payload was not JSON")
                return
            }
            database.saveState(json: json)
            if let name = ((state["settings"] as? [String: Any])?["appName"] as? String) ?? (state["appName"] as? String) {
                appName = name
                window?.title = name
            }

        case "export":
            guard let exportPayload = payload as? [String: Any] else { return }
            let suggested = (exportPayload["suggestedName"] as? String) ?? "kanbanflow_backup.json"
            let state = exportPayload["payload"]
            exportState(state, suggestedName: suggested)

        case "import":
            importState()

        case "dbInfo":
            sendDbInfo()

        case "revealDB":
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: database.path)])

        case "setAppName":
            if let name = (payload as? [String: Any])?["name"] as? String, !name.isEmpty {
                appName = name
                window?.title = name
                database.setAppName(name)
            }

        case "log":
            if let text = payload as? String { print("Hamster's Kanban JS: \(text)") }
            else if let text = payload { print("Hamster's Kanban JS: \(text)") }

        default:
            print("Hamster's Kanban: unknown bridge action \(action)")
        }
    }

    private func prettyJSONCompact(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func sendDbInfo() {
        guard let webView else { return }
        let info = database.stats()
        webView.evaluateJavaScript("window.onNativeDbInfo(\(jsLiteral(info)));", completionHandler: nil)
    }

    func performImport() {
        importState()
    }

    func performReveal() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: database.path)])
    }

    private func exportState(_ state: Any?, suggestedName: String) {
        guard let state, let text = prettyJSONString(from: state) else {
            print("Hamster's Kanban: export failed, state was not JSON")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export \(appName) Backup"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                self?.database.recordBackup(json: text)
                print("Hamster's Kanban: exported database backup to \(url.path)")
            } catch {
                self?.showError("Could not write the backup file.", detail: error.localizedDescription)
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func importState() {
        let panel = NSOpenPanel()
        panel.title = "Import \(appName) Backup"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                guard text.data(using: .utf8).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) != nil else {
                    self?.showError("That file is not valid JSON.")
                    return
                }
                if let current = self?.database.loadState() {
                    self?.database.recordBackup(json: current)
                }
                self?.webView?.evaluateJavaScript("window.onNativeImportState(\(jsonStringLiteral(text)));", completionHandler: { _, error in
                    if let error {
                        print("Hamster's Kanban: import JS error: \(error.localizedDescription)")
                    }
                })
                print("Hamster's Kanban: importing backup from \(url.path)")
            } catch {
                self?.showError("Could not read the backup file.", detail: error.localizedDescription)
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func showError(_ message: String, detail: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        if let detail { alert.informativeText = detail }
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, WKUIDelegate, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var bridge: NativeBridge!
    private var database: KanbanDatabase!

    func applicationDidFinishLaunching(_ notification: Notification) {
        database = KanbanDatabase()
        bridge = NativeBridge(database: database)

        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(bridge, name: "kanbanDB")

        var injected = """
        (function () {
            function send(text) {
                try { window.webkit.messageHandlers.kanbanDB.postMessage({ action: 'log', payload: String(text) }); } catch (e) {}
            }
            window.addEventListener('error', function (event) {
                send('JS error: ' + event.message + ' @ ' + (event.filename || '') + ':' + (event.lineno || 0));
            });
            window.addEventListener('unhandledrejection', function (event) {
                send('Unhandled rejection: ' + (event.reason && event.reason.message ? event.reason.message : event.reason));
            });
        })();
        """

        if let initialState = database.loadState() {
            injected += "\nwindow.KANBAN_INITIAL_STATE = " + jsonStringLiteral(initialState) + ";"
        }

        contentController.addUserScript(WKUserScript(
            source: injected,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        configuration.userContentController = contentController
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.websiteDataStore = .default()

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = self
        webView.navigationDelegate = self

        bridge.webView = webView

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 920),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = database.appName()
        window.minSize = NSSize(width: 900, height: 600)
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("HamstersKanbanMainWindow")
        bridge.setWindow(window)

        buildMenu()
        loadInterface()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadInterface() {
        guard let htmlURL = Bundle.main.url(forResource: "kanban", withExtension: "html") else {
            let alert = NSAlert()
            alert.messageText = "Hamster's Kanban is missing its interface"
            alert.informativeText = "The kanban.html resource could not be found in the application bundle."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: Bundle.main.resourceURL ?? htmlURL.deletingLastPathComponent())
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(database.appName())", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let importItem = NSMenuItem(title: "Import Backup…", action: #selector(importBackup), keyEquivalent: "i")
        importItem.target = self
        importItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(importItem)

        let exportItem = NSMenuItem(title: "Export Backup…", action: #selector(exportBackup), keyEquivalent: "e")
        exportItem.target = self
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(exportItem)

        let revealItem = NSMenuItem(title: "Reveal Database in Finder", action: #selector(revealDatabase), keyEquivalent: "")
        revealItem.target = self
        appMenu.addItem(revealItem)
        appMenu.addItem(.separator())

        appMenu.addItem(withTitle: "Hide \(database.appName())", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(database.appName())", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (important for text fields in the web view)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        // Cmd+Z first asks the HTML layer. If a text field is focused the web
        // view performs its normal text undo; otherwise the board state is
        // restored from the in-page undo stack.
        let undoItem = NSMenuItem(title: "Undo", action: #selector(menuUndo), keyEquivalent: "z")
        undoItem.target = self
        editMenu.addItem(undoItem)
        let redoItem = NSMenuItem(title: "Redo", action: #selector(menuRedo), keyEquivalent: "Z")
        redoItem.target = self
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+")
        zoomIn.target = self
        viewMenu.addItem(zoomIn)
        let zoomOut = NSMenuItem(title: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-")
        zoomOut.target = self
        viewMenu.addItem(zoomOut)
        let actualSize = NSMenuItem(title: "Actual Size", action: #selector(actualSize), keyEquivalent: "0")
        actualSize.target = self
        viewMenu.addItem(actualSize)
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = database.appName()
        alert.informativeText = "A native macOS kanban board.\n\nDatabase:\n\(database.path)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openSettings() {
        webView.evaluateJavaScript("showSettingsModal();", completionHandler: nil)
    }

    @objc private func menuUndo(_ sender: Any?) {
        webView.evaluateJavaScript("window.kanbanUndoRequest ? window.kanbanUndoRequest() : 'text'") { [weak self] result, _ in
            guard let self else { return }
            if let mode = result as? String, mode == "app" { return }

            // A text field is focused: keep the normal typing undo behaviour.
            if let manager = self.webView.undoManager, manager.canUndo {
                manager.undo()
            } else {
                self.webView.evaluateJavaScript("document.execCommand('undo');", completionHandler: nil)
            }
        }
    }

    @objc private func menuRedo(_ sender: Any?) {
        if let manager = webView.undoManager, manager.canRedo {
            manager.redo()
        } else {
            webView.evaluateJavaScript("document.execCommand('redo');", completionHandler: nil)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(menuUndo) || menuItem.action == #selector(menuRedo) {
            return true
        }
        return true
    }

    @objc private func importBackup() {
        bridge.performImport()
    }

    @objc private func exportBackup() {
        webView.evaluateJavaScript("exportAllBoards();", completionHandler: nil)
    }

    @objc private func revealDatabase() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: database.path)])
    }

    @objc private func zoomIn() {
        webView.pageZoom = min(2.0, webView.pageZoom + 0.1)
    }

    @objc private func zoomOut() {
        webView.pageZoom = max(0.6, webView.pageZoom - 0.1)
    }

    @objc private func actualSize() {
        webView.pageZoom = 1.0
    }

    // MARK: WKUIDelegate (alert / confirm / prompt support)

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = database.appName()
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = database.appName()
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = database.appName()
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("Hamster's Kanban: interface loaded")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("Hamster's Kanban: navigation failed: \(error.localizedDescription)")
    }
}

// MARK: - Self test

private func runSelfTest() -> Never {
    let tempPath = NSTemporaryDirectory() + "kanbanflow-selftest-\(UUID().uuidString).sqlite"
    let database = KanbanDatabase(path: tempPath)
    let sample: [String: Any] = [
        "version": 2,
        "boardOrder": ["b1"],
        "columnOrder": ["c1", "c2"],
        "currentBoard": "b1",
        "currentTheme": "dark",
        "settings": ["appName": "Self Test"],
        "boards": [
            "b1": [
                "name": "Test Board",
                "columns": [
                    "c1": ["title": "To Do", "order": 0],
                    "c2": ["title": "Done", "order": 1]
                ],
                "cards": [
                    "c1": [[
                        "id": "x1", "title": "Task", "dueDate": "2026-01-01", "dueDateEnd": "2026-01-03",
                        "description": "desc", "label": "blue", "priority": "high",
                        "assignee": "A", "avatar": "👤", "subtasks": 1, "subtasksTotal": 3,
                        "createdAt": "2026-01-01", "comments": [], "activity": []
                    ]],
                    "c2": []
                ],
                "separators": [["id": "s1", "label": "Week 1", "color": "#e94558", "before": "c2"]]
            ]
        ]
    ]

    let json = prettyJSONString(from: sample)!
    database.saveState(json: json)

    let loaded = database.loadState() ?? ""
    let stats = database.stats()
    let report: [String: Any] = [
        "loadedMatches": loaded == json,
        "appName": database.appName(),
        "cards": stats["cards"] ?? -1,
        "separators": stats["separators"] ?? -1,
        "columns": stats["columns"] ?? -1,
        "boards": stats["boards"] ?? -1,
        "backupRecorded": {
            database.recordBackup(json: json)
            return database.backupCount() == 1
        }()
    ]
    let output = prettyJSONString(from: report) ?? "{}"
    print(output)
    try? FileManager.default.removeItem(atPath: tempPath)
    try? FileManager.default.removeItem(atPath: tempPath + "-wal")
    try? FileManager.default.removeItem(atPath: tempPath + "-shm")
    exit(0)
}

// MARK: - Entry point

if CommandLine.arguments.contains("--selftest") {
    runSelfTest()
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
