import AppKit
import Foundation
import Testing
@testable import DualFinderApp
@testable import DualFinderCore

@Suite("FilePane interactions")
struct FilePaneInteractionTests {
    @MainActor
    @Test("new folder shortcut path creates a folder and requests inline rename")
    func newFolderShortcutPathCreatesFolderAndRequestsInlineRename() throws {
        let root = try AppTestTemporaryDirectory()
        let model = makeLocalModel(initialURL: root.url)

        model.createFolderAndRequestRename(in: .left)

        let created = root.url.appendingPathComponent("New Folder").standardizedFileURL
        #expect(FileManager.default.fileExists(atPath: created.path))
        #expect(model.pane(for: .left).selectedItemURLs == [created])
        #expect(model.inlineRenameRequest?.side == .left)
        #expect(model.inlineRenameRequest?.url == created)
    }

    @MainActor
    @Test("renaming a newly-created folder keeps selection equal to the rendered row URL")
    func renamingNewFolderKeepsSelectionEqualToRenderedRowURL() throws {
        let root = try AppTestTemporaryDirectory()
        let model = makeLocalModel(initialURL: root.url)
        let created = try #require(model.createFolder(in: .left))

        let renamed = try #require(model.renameItem(created, to: "Finished", on: .left))
        let selected = try #require(model.pane(for: .left).selectedItemURLs.first)
        let renderedRow = try #require(model.items(for: .left).first { $0.name == "Finished" })

        #expect(selected == renamed)
        #expect(renderedRow.url == selected)
        #expect(renderedRow.isDirectoryLike)
    }

    @MainActor
    @Test("switches a pane to android view and lists the selected device")
    func switchesPaneToAndroidView() throws {
        let root = try AppTestTemporaryDirectory()
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(
                exitCode: 0,
                stdout: """
                List of devices attached
                emulator-5554 device model:Pixel_8

                """,
                stderr: ""
            ),
            CommandResult(
                exitCode: 0,
                stdout: androidDirectoryListing(["Download": "d"]),
                stderr: ""
            )
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)

        model.switchPaneToAndroid(.left)

        #expect(model.isAndroidPane(.left))
        #expect(model.androidDeviceSerial(for: .left) == "emulator-5554")
        #expect(model.pane(for: .left).selectedURL == AndroidFileURL.url(deviceSerial: "emulator-5554", path: "/sdcard"))
        #expect(model.items(for: .left).map(\.name) == ["Download"])
    }

    @MainActor
    @Test("android view button refreshes devices and current remote directory")
    func androidViewButtonRefreshesDevicesAndCurrentDirectory() throws {
        let root = try AppTestTemporaryDirectory()
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(
                exitCode: 0,
                stdout: """
                List of devices attached
                emulator-5554 device model:Pixel_8

                """,
                stderr: ""
            ),
            CommandResult(exitCode: 0, stdout: androidDirectoryListing(["Before": "d"]), stderr: ""),
            CommandResult(
                exitCode: 0,
                stdout: """
                List of devices attached
                emulator-5554 device model:Pixel_8

                """,
                stderr: ""
            ),
            CommandResult(exitCode: 0, stdout: androidDirectoryListing(["After": "d"]), stderr: "")
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)
        model.switchPaneToAndroid(.left)

        model.refreshAndroidStateForViewButton(on: .left)

        #expect(model.androidDevices.map(\.serial) == ["emulator-5554"])
        #expect(model.items(for: .left).map(\.name) == ["After"])
        #expect(runner.calls.map(\.arguments) == [
            ["adb", "devices", "-l"],
            ["adb", "-s", "emulator-5554", "shell", "ls -la '/sdcard/'"],
            ["adb", "devices", "-l"],
            ["adb", "-s", "emulator-5554", "shell", "ls -la '/sdcard/'"]
        ])
    }

    @MainActor
    @Test("toolbar Android device refresh is cached and expires")
    func toolbarAndroidDeviceRefreshIsCachedAndExpires() throws {
        let root = try AppTestTemporaryDirectory()
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(
                exitCode: 0,
                stdout: """
                List of devices attached
                emulator-5554 device model:Pixel_8

                """,
                stderr: ""
            ),
            CommandResult(
                exitCode: 0,
                stdout: """
                List of devices attached
                emulator-5556 device model:Pixel_9

                """,
                stderr: ""
            )
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)
        let start = Date(timeIntervalSince1970: 1_000)

        model.refreshAndroidDevicesForToolbar(now: start, staleAfter: 5)
        model.refreshAndroidDevicesForToolbar(now: start.addingTimeInterval(1), staleAfter: 5)
        #expect(runner.calls.map(\.arguments) == [
            ["adb", "devices", "-l"]
        ])
        #expect(model.androidDevices.map(\.serial) == ["emulator-5554"])

        model.refreshAndroidDevicesForToolbar(now: start.addingTimeInterval(6), staleAfter: 5)
        #expect(runner.calls.map(\.arguments) == [
            ["adb", "devices", "-l"],
            ["adb", "devices", "-l"]
        ])
        #expect(model.androidDevices.map(\.serial) == ["emulator-5556"])
    }

    @MainActor
    @Test("toolbar Android device refresh caches failed attempts briefly")
    func toolbarAndroidDeviceRefreshCachesFailedAttemptsBriefly() throws {
        let root = try AppTestTemporaryDirectory()
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(exitCode: 1, stdout: "", stderr: "adb unavailable"),
            CommandResult(
                exitCode: 0,
                stdout: """
                List of devices attached
                emulator-5554 device model:Pixel_8

                """,
                stderr: ""
            )
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)
        let start = Date(timeIntervalSince1970: 2_000)

        model.refreshAndroidDevicesForToolbar(now: start, staleAfter: 5)
        model.refreshAndroidDevicesForToolbar(now: start.addingTimeInterval(1), staleAfter: 5)
        #expect(runner.calls.map(\.arguments) == [
            ["adb", "devices", "-l"]
        ])
        #expect(model.androidDevices.isEmpty)

        model.refreshAndroidDevicesForToolbar(now: start.addingTimeInterval(6), staleAfter: 5)
        #expect(runner.calls.map(\.arguments) == [
            ["adb", "devices", "-l"],
            ["adb", "devices", "-l"]
        ])
        #expect(model.androidDevices.map(\.serial) == ["emulator-5554"])
    }

    @MainActor
    @Test("android pane opens selected folders without using local file existence")
    func androidPaneNavigatesIntoSelectedFolder() throws {
        let root = try AppTestTemporaryDirectory()
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(exitCode: 0, stdout: androidDirectoryListing(["Child": "d"]), stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: "")
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)
        model.switchPaneToAndroid(.left, deviceSerial: "emulator-5554")

        model.activateItem(AndroidFileURL.url(deviceSerial: "emulator-5554", path: "/sdcard/Child"), on: .left)

        #expect(model.pane(for: .left).selectedURL == AndroidFileURL.url(deviceSerial: "emulator-5554", path: "/sdcard/Child"))
        #expect(runner.calls.last?.arguments == [
            "adb", "-s", "emulator-5554", "shell",
            "ls -la '/sdcard/Child/'"
        ])
    }

    @MainActor
    @Test("copies local selection to android pane")
    func copiesLocalSelectionToAndroidPane() async throws {
        let root = try AppTestTemporaryDirectory()
        let localFile = root.url.appendingPathComponent("local.txt")
        try "local".write(to: localFile, atomically: true, encoding: .utf8)
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(exitCode: 0, stdout: "", stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: "")
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)

        model.refresh(.left)
        model.switchPaneToAndroid(.right, deviceSerial: "emulator-5554")
        model.replaceSelection([localFile.standardizedFileURL], on: .left, source: "test")
        model.copySelection(from: .left)

        #expect(model.fileOperationQueue.contains { $0.kind == .copy && $0.status != .failed })
        try await waitForCall(
            runner,
            arguments: ["adb", "-s", "emulator-5554", "push", localFile.path, "/sdcard/"]
        )
    }

    @MainActor
    @Test("android history back restores local pane mode")
    func androidHistoryBackRestoresLocalPaneMode() throws {
        let root = try AppTestTemporaryDirectory()
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(exitCode: 0, stdout: "", stderr: "")
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)

        model.switchPaneToAndroid(.left, deviceSerial: "emulator-5554")
        model.navigateBack(.left)

        #expect(!model.isAndroidPane(.left))
        #expect(model.pane(for: .left).selectedURL == root.url.standardizedFileURL)
    }

    @MainActor
    @Test("navigate up skips deleted parent directories")
    func navigateUpSkipsDeletedParentDirectories() throws {
        let root = try AppTestTemporaryDirectory()
        let parent = root.url.appendingPathComponent("Parent", isDirectory: true)
        let child = parent.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let model = makeLocalModel(initialURL: child)

        try FileManager.default.removeItem(at: parent)
        model.navigateUp(.left)

        #expect(model.pane(for: .left).selectedURL == root.url.standardizedFileURL)
    }

    @MainActor
    @Test("refresh recovers to existing ancestor when current directory was deleted")
    func refreshRecoversToExistingAncestorWhenCurrentDirectoryWasDeleted() throws {
        let root = try AppTestTemporaryDirectory()
        let parent = root.url.appendingPathComponent("Parent", isDirectory: true)
        let child = parent.appendingPathComponent("Child", isDirectory: true)
        let visible = root.url.appendingPathComponent("visible.txt")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "visible".write(to: visible, atomically: true, encoding: .utf8)
        let model = makeLocalModel(initialURL: child)

        try FileManager.default.removeItem(at: parent)
        model.refresh(.left)

        #expect(model.pane(for: .left).selectedURL == root.url.standardizedFileURL)
        #expect(model.items(for: .left).map(\.url).contains(visible.standardizedFileURL))
    }

    @MainActor
    @Test("copies android selection to local pane")
    func copiesAndroidSelectionToLocalPane() async throws {
        let root = try AppTestTemporaryDirectory()
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(exitCode: 0, stdout: androidDirectoryListing(["photo.jpg": "-"]), stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: ""),
            CommandResult(exitCode: 0, stdout: androidDirectoryListing(["photo.jpg": "-"]), stderr: "")
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)
        model.switchPaneToAndroid(.left, deviceSerial: "emulator-5554")
        model.replaceSelection([AndroidFileURL.url(deviceSerial: "emulator-5554", path: "/sdcard/photo.jpg")], on: .left, source: "test")

        model.copySelection(from: .left)

        #expect(model.fileOperationQueue.contains { $0.kind == .copy && $0.status != .failed })
        try await waitForCall(
            runner,
            arguments: ["adb", "-s", "emulator-5554", "pull", "/sdcard/photo.jpg", root.url.standardizedFileURL.path + "/"]
        )
    }

    @MainActor
    @Test("large android copy skips per-file byte estimates")
    func largeAndroidCopySkipsPerFileByteEstimates() async throws {
        let root = try AppTestTemporaryDirectory()
        let names = (0..<33).map { "file-\($0).txt" }
        let initialListing = androidDirectoryListing(
            Dictionary(uniqueKeysWithValues: names.map { ($0, "-") })
        )
        let runner = AppRecordingCommandRunner(
            results: [CommandResult(exitCode: 0, stdout: initialListing, stderr: "")]
                + Array(repeating: CommandResult(exitCode: 0, stdout: "", stderr: ""), count: names.count)
                + [CommandResult(exitCode: 0, stdout: initialListing, stderr: "")]
        )
        let model = makeModel(initialURL: root.url, androidRunner: runner)
        model.switchPaneToAndroid(.left, deviceSerial: "emulator-5554")
        model.replaceSelection(
            Set(names.map { AndroidFileURL.url(deviceSerial: "emulator-5554", path: "/sdcard/\($0)") }),
            on: .left,
            source: "test"
        )

        model.copySelection(from: .left)

        try await waitForCall(
            runner,
            arguments: ["adb", "-s", "emulator-5554", "pull", "/sdcard/file-0.txt", root.url.standardizedFileURL.path + "/"]
        )
        #expect(!runner.calls.contains { call in
            call.arguments.contains { $0.contains("du -sk") }
        })
    }

    @MainActor
    @Test("android folder copy skips directory byte estimates")
    func androidFolderCopySkipsDirectoryByteEstimates() async throws {
        let root = try AppTestTemporaryDirectory()
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(exitCode: 0, stdout: androidDirectoryListing(["Folder": "d"]), stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: ""),
            CommandResult(exitCode: 0, stdout: androidDirectoryListing(["Folder": "d"]), stderr: "")
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)
        model.switchPaneToAndroid(.left, deviceSerial: "emulator-5554")
        model.replaceSelection(
            [AndroidFileURL.url(deviceSerial: "emulator-5554", path: "/sdcard/Folder")],
            on: .left,
            source: "test"
        )

        model.copySelection(from: .left)

        try await waitForCall(
            runner,
            arguments: ["adb", "-s", "emulator-5554", "pull", "/sdcard/Folder", root.url.standardizedFileURL.path + "/"]
        )
        #expect(!runner.calls.contains { call in
            call.arguments.contains { $0.contains("du -sk") }
        })
    }

    @MainActor
    @Test("renames and deletes android items")
    func renamesAndDeletesAndroidItems() async throws {
        let root = try AppTestTemporaryDirectory()
        let oldURL = AndroidFileURL.url(deviceSerial: "emulator-5554", path: "/sdcard/old.txt")
        let renamedURL = AndroidFileURL.url(deviceSerial: "emulator-5554", path: "/sdcard/new.txt")
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(exitCode: 0, stdout: androidDirectoryListing(["old.txt": "-"]), stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: ""),
            CommandResult(exitCode: 0, stdout: androidDirectoryListing(["new.txt": "-"]), stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: "")
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)
        model.switchPaneToAndroid(.left, deviceSerial: "emulator-5554")

        model.renameItem(oldURL, to: "new.txt", on: .left)
        model.replaceSelection([renamedURL], on: .left, source: "test")
        model.trashSelection(from: .left)

        #expect(runner.containsCall(arguments: [
            "adb", "-s", "emulator-5554", "shell", "mv '/sdcard/old.txt' '/sdcard/new.txt'"
        ]))
        #expect(model.fileOperationQueue.contains { $0.kind == .trash && $0.status != .failed })
        try await waitForCall(
            runner,
            arguments: ["adb", "-s", "emulator-5554", "shell", "rm -rf '/sdcard/new.txt'"]
        )
        #expect(!runner.calls.contains { call in
            call.arguments.contains { $0.contains("du -sk") }
        })
    }

    @MainActor
    @Test("android to android copy uses listed file sizes without du")
    func androidToAndroidCopyUsesListedFileSizesWithoutDU() async throws {
        let root = try AppTestTemporaryDirectory()
        let listing = androidDirectoryListing(["Source.txt": "-"])
        let runner = AppRecordingCommandRunner(results: [
            CommandResult(exitCode: 0, stdout: listing, stderr: ""),
            CommandResult(exitCode: 0, stdout: androidDirectoryListing([:]), stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: ""),
            CommandResult(exitCode: 0, stdout: listing, stderr: ""),
            CommandResult(exitCode: 0, stdout: androidDirectoryListing(["Source.txt": "-"]), stderr: "")
        ])
        let model = makeModel(initialURL: root.url, androidRunner: runner)
        model.switchPaneToAndroid(.left, deviceSerial: "emulator-5554")
        model.switchPaneToAndroid(.right, deviceSerial: "emulator-5554")
        model.replaceSelection(
            [AndroidFileURL.url(deviceSerial: "emulator-5554", path: "/sdcard/Source.txt")],
            on: .left,
            source: "test"
        )

        model.copySelection(from: .left)

        try await waitForCall(
            runner,
            arguments: ["adb", "-s", "emulator-5554", "shell", "cp -R '/sdcard/Source.txt' '/sdcard/'"]
        )
        #expect(!runner.calls.contains { call in
            call.arguments.contains { $0.contains("du -sk") }
        })
    }

    @MainActor
    @Test("flat view uses selected file parent folder")
    func flatViewUsesSelectedFileParentFolder() throws {
        let root = try AppTestTemporaryDirectory()
        let nested = root.url.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let selectedFile = root.url.appendingPathComponent("Template Manager.html")
        try "html".write(to: selectedFile, atomically: true, encoding: .utf8)
        try "readme".write(to: nested.appendingPathComponent("ReadMe.txt"), atomically: true, encoding: .utf8)

        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = DualFinderViewModel(
            initialURL: root.url,
            sortRuleStore: FolderSortRuleStore(defaults: defaults, key: "sort"),
            paneSessionStore: PaneSessionStore(defaults: defaults, key: "session"),
            folderBookmarkStore: FolderBookmarkStore(defaults: defaults, key: "bookmarks"),
            uiLayoutPreferencesStore: UILayoutPreferencesStore(defaults: defaults, key: "layout"),
            logger: AppTestLogger()
        )
        model.refresh(.left)
        model.replaceSelection([selectedFile.standardizedFileURL], on: .left, source: "test")

        model.toggleFlatView(on: .left)

        #expect(model.flatViewRoot(for: .left) == root.url.standardizedFileURL)
        #expect(model.items(for: .left).map(\.url).contains(selectedFile.standardizedFileURL))
        #expect(model.items(for: .left).map(\.url).contains(nested.appendingPathComponent("ReadMe.txt").standardizedFileURL))
        #expect(model.items(for: .left).allSatisfy { !$0.isDirectoryLike })

        model.toggleFlatView(on: .left)

        #expect(model.flatViewRoot(for: .left) == nil)
        #expect(model.pane(for: .left).selectedItemURLs == [selectedFile.standardizedFileURL])
    }

    @MainActor
    @Test("encoding column shows cached values first and fills uncached values asynchronously")
    func encodingColumnScansAsynchronously() async throws {
        let root = try AppTestTemporaryDirectory()
        let cachedFile = root.url.appendingPathComponent("cached.txt")
        let uncachedFile = root.url.appendingPathComponent("uncached.txt")
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        try "cached".write(to: cachedFile, atomically: true, encoding: .utf8)
        try "uncached".write(to: uncachedFile, atomically: true, encoding: .utf8)
        _ = try TextEncodingConversionService(logger: AppTestLogger(), cache: cache).detectFileEncoding(cachedFile)

        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = DualFinderViewModel(
            initialURL: root.url,
            sortRuleStore: FolderSortRuleStore(defaults: defaults, key: "sort"),
            paneSessionStore: PaneSessionStore(defaults: defaults, key: "session"),
            folderBookmarkStore: FolderBookmarkStore(defaults: defaults, key: "bookmarks"),
            textEncodingCache: cache,
            uiLayoutPreferencesStore: UILayoutPreferencesStore(defaults: defaults, key: "layout"),
            logger: AppTestLogger()
        )

        model.setEncodingColumnVisible(true)
        let initialItems = model.items(for: .left)

        #expect(initialItems.first(where: { $0.url == cachedFile.standardizedFileURL })?.textEncoding == "utf-8")
        #expect(initialItems.first(where: { $0.url == uncachedFile.standardizedFileURL })?.textEncoding == nil)

        for _ in 0..<40 {
            if model.items(for: .left).first(where: { $0.url == uncachedFile.standardizedFileURL })?.textEncoding == "utf-8" {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(model.items(for: .left).first(where: { $0.url == uncachedFile.standardizedFileURL })?.textEncoding == "utf-8")
    }

    @Test("formats file sizes with three fractional digits")
    func formatsFileSizesWithThreeFractionalDigits() {
        #expect(FileSizeText.format(1_234_567) == "1.235 MB")
        #expect(FileSizeText.format(699_000) == "699.000 KB")
        #expect(FileSizeText.format(nil) == "--")
    }

    @Test("keeps visually deleted similar files in the review snapshot")
    func keepsVisuallyDeletedSimilarFilesInReviewSnapshot() {
        let first = file("一千零一夜 2003.txt")
        let second = file("一千零一夜 2008.txt")
        let third = file("一千零一夜 2010.txt")
        var state = SimilarFileReviewState(groups: [
            SimilarFileNameGroup(id: "txt|一千零一夜", items: [first, second, third])
        ])

        state.markVisuallyDeleted([second.url])

        #expect(state.visibleItems.map(\.url) == [first.url, second.url, third.url])
        #expect(state.isVisuallyDeleted(second.url))
        #expect(!state.isVisuallyDeleted(first.url))
    }

    @Test("moves focus to next undeleted similar file after deletion")
    func movesFocusToNextUndeletedSimilarFileAfterDeletion() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])
        var state = SimilarFileReviewState(groups: [
            SimilarFileNameGroup(id: "txt|a", items: urls.map(file))
        ])

        state.markVisuallyDeleted([urls[1]])

        #expect(state.replacementSelection(afterDeleting: [urls[1]]) == [urls[2]])
    }

    @Test("moves focus to previous undeleted similar file when deleted item has no next item")
    func movesFocusToPreviousUndeletedSimilarFileWhenNoNextItemExists() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])
        var state = SimilarFileReviewState(groups: [
            SimilarFileNameGroup(id: "txt|a", items: urls.map(file))
        ])

        state.markVisuallyDeleted([urls[2]])

        #expect(state.replacementSelection(afterDeleting: [urls[2]]) == [urls[1]])
    }

    @Test("skips visually deleted rows when moving focus after deletion")
    func skipsVisuallyDeletedRowsWhenMovingFocusAfterDeletion() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])
        var state = SimilarFileReviewState(groups: [
            SimilarFileNameGroup(id: "txt|a", items: urls.map(file))
        ])

        state.markVisuallyDeleted([urls[1], urls[2]])

        #expect(state.replacementSelection(afterDeleting: [urls[1]]) == [urls[0]])
    }

    @Test("command click toggles selection on mouse up without disturbing mouse down selection")
    func commandClickTogglesSelectionOnMouseUp() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])
        let selected: Set<URL> = [urls[0]]

        let mouseDownSelection = FileRowSelectionReducer.selectionAfterMouseDown(
            target: urls[1],
            currentSelection: selected,
            orderedURLs: urls,
            modifierFlags: [.command]
        )
        let mouseUpSelection = FileRowSelectionReducer.selectionAfterMouseUp(
            target: urls[1],
            currentSelection: selected,
            orderedURLs: urls,
            modifierFlags: [.command]
        )

        #expect(mouseDownSelection == nil)
        #expect(mouseUpSelection == [urls[0], urls[1]])
    }

    @Test("selection snapshot matches exact and standardized file URLs")
    func selectionSnapshotMatchesExactAndStandardizedFileURLs() {
        let exact = URL(fileURLWithPath: "/tmp/DualFinder/a.txt").standardizedFileURL
        let nonStandard = URL(fileURLWithPath: "/tmp/DualFinder/../DualFinder/b.txt")
        let snapshot = FileSelectionSnapshot(selection: [exact, nonStandard])

        #expect(snapshot.contains(exact))
        #expect(snapshot.contains(nonStandard.standardizedFileURL))
        #expect(!snapshot.contains(URL(fileURLWithPath: "/tmp/DualFinder/c.txt")))
    }

    @Test("keyboard navigation starts from mouse-updated anchor")
    func keyboardNavigationStartsFromMouseUpdatedAnchor() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt", "d.txt"])
        let staleSelection: Set<URL> = [urls[0]]
        let mouseFocusedURL = urls[2]

        let nextSelection = FileKeyboardSelectionNavigator.selectionAfterMove(
            anchorURL: mouseFocusedURL,
            currentSelection: staleSelection,
            orderedURLs: urls,
            delta: 1
        )

        #expect(nextSelection == [urls[3]])
    }

    @Test("keyboard navigation falls back to current selection without anchor")
    func keyboardNavigationFallsBackToCurrentSelectionWithoutAnchor() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])

        let nextSelection = FileKeyboardSelectionNavigator.selectionAfterMove(
            anchorURL: nil,
            currentSelection: [urls[1]],
            orderedURLs: urls,
            delta: -1
        )

        #expect(nextSelection == [urls[0]])
    }

    @Test("keyboard navigation skips visually deleted similar rows")
    func keyboardNavigationSkipsVisuallyDeletedSimilarRows() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt", "d.txt"])

        let nextSelection = FileKeyboardSelectionNavigator.selectionAfterMove(
            anchorURL: urls[0],
            currentSelection: [urls[0]],
            orderedURLs: urls,
            unavailableURLs: [urls[1], urls[2]],
            delta: 1
        )

        #expect(nextSelection == [urls[3]])
    }

    @MainActor
    @Test("merge keeps explicit order and focuses the merged file")
    func mergeKeepsExplicitOrderAndFocusesMergedFile() throws {
        let root = try AppTestTemporaryDirectory()
        let first = root.url.appendingPathComponent("first.txt")
        let second = root.url.appendingPathComponent("second.txt")
        let third = root.url.appendingPathComponent("third.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)
        try "three".write(to: third, atomically: true, encoding: .utf8)
        let model = makeLocalModel(initialURL: root.url)

        model.refresh(.left)
        model.mergeFiles(
            [third.standardizedFileURL, first.standardizedFileURL, second.standardizedFileURL],
            named: "merged.txt",
            on: .left
        )

        let merged = root.url.appendingPathComponent("merged.txt").standardizedFileURL
        #expect(try String(contentsOf: merged, encoding: .utf8) == "three\none\ntwo")
        #expect(model.pane(for: .left).selectedItemURLs == [merged])
        #expect(model.activePaneSide == .left)
        #expect(model.paneFocusRequest?.side == .left)
        #expect(model.paneFocusRequest?.revealURL == merged)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(!FileManager.default.fileExists(atPath: third.path))
    }

    @MainActor
    @Test("split file request previews one selected txt file")
    func splitFileRequestPreviewsOneSelectedTXTFile() throws {
        let root = try AppTestTemporaryDirectory()
        let file = root.url.appendingPathComponent("合集.txt")
        try """
        第01篇 第一篇
        正文一
        第02篇 第二篇
        正文二
        """.write(to: file, atomically: true, encoding: .utf8)
        let model = makeLocalModel(initialURL: root.url)

        model.refresh(.left)
        model.replaceSelection([file.standardizedFileURL], on: .left, source: "test")
        model.requestSplitFileDialog(on: .left)

        #expect(model.splitFileDialogRequest?.preview.chapters.map(\.outputFileName) == [
            "第一篇.txt",
            "第二篇.txt"
        ])
        #expect(model.statusMessage == "Split preview: 2 file(s)")
    }

    @MainActor
    @Test("split file confirmation creates chapter files and deletes original")
    func splitFileConfirmationCreatesChapterFilesAndDeletesOriginal() throws {
        let root = try AppTestTemporaryDirectory()
        let file = root.url.appendingPathComponent("合集.txt")
        try """
        第01篇 第一篇
        正文一
        第02篇 第二篇
        正文二
        """.write(to: file, atomically: true, encoding: .utf8)
        let model = makeLocalModel(initialURL: root.url)

        model.refresh(.left)
        model.replaceSelection([file.standardizedFileURL], on: .left, source: "test")
        model.requestSplitFileDialog(on: .left)
        let preview = try #require(model.splitFileDialogRequest?.preview)

        model.splitFile(preview, on: .left)

        let first = root.url.appendingPathComponent("第一篇.txt").standardizedFileURL
        let second = root.url.appendingPathComponent("第二篇.txt").standardizedFileURL
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: first, encoding: .utf8).contains("正文一"))
        #expect(try String(contentsOf: second, encoding: .utf8).contains("正文二"))
        #expect(model.pane(for: .left).selectedItemURLs == [first, second])
    }

    private func file(_ name: String) -> FileItem {
        file(URL(fileURLWithPath: "/tmp/\(name)"))
    }

    private func file(_ url: URL) -> FileItem {
        FileItem(
            url: url,
            name: url.lastPathComponent,
            kind: .file,
            type: "text",
            size: 1,
            modifiedAt: nil,
            isHidden: false
        )
    }

    private func fileURLs(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/\($0)") }
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "DualFinder.FilePaneInteractionTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func androidDirectoryListing(_ entries: [String: String]) -> String {
        let rows = entries.sorted { $0.key < $1.key }.map { name, kind in
            let mode = kind == "d" ? "drwxrwx--x" : "-rw-rw----"
            return "\(mode) 1 root sdcard_rw 4096 2026-06-18 10:00 \(name)"
        }
        return ([
            "total \(rows.count)",
            "drwxrwx--x 2 root sdcard_rw 4096 2026-06-18 10:00 .",
            "drwxrwx--x 4 root sdcard_rw 4096 2026-06-18 09:00 .."
        ] + rows).joined(separator: "\n") + "\n"
    }

    private func waitForCall(
        _ runner: AppRecordingCommandRunner,
        arguments: [String],
        attempts: Int = 40
    ) async throws {
        for _ in 0..<attempts {
            if runner.containsCall(arguments: arguments) {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("Timed out waiting for command: \(arguments.joined(separator: " "))")
    }

    @MainActor
    private func makeModel(
        initialURL: URL,
        androidRunner: AppRecordingCommandRunner
    ) -> DualFinderViewModel {
        let (defaults, suiteName) = makeDefaults()
        defaults.removePersistentDomain(forName: suiteName)
        return DualFinderViewModel(
            initialURL: initialURL,
            sortRuleStore: FolderSortRuleStore(defaults: defaults, key: "sort"),
            paneSessionStore: PaneSessionStore(defaults: defaults, key: "session"),
            folderBookmarkStore: FolderBookmarkStore(defaults: defaults, key: "bookmarks"),
            uiLayoutPreferencesStore: UILayoutPreferencesStore(defaults: defaults, key: "layout"),
            androidFileService: AndroidFileService(adbExecutable: "/usr/bin/env", commandRunner: androidRunner),
            logger: AppTestLogger()
        )
    }

    @MainActor
    private func makeLocalModel(initialURL: URL) -> DualFinderViewModel {
        let (defaults, suiteName) = makeDefaults()
        defaults.removePersistentDomain(forName: suiteName)
        return DualFinderViewModel(
            initialURL: initialURL,
            sortRuleStore: FolderSortRuleStore(defaults: defaults, key: "sort"),
            paneSessionStore: PaneSessionStore(defaults: defaults, key: "session"),
            folderBookmarkStore: FolderBookmarkStore(defaults: defaults, key: "bookmarks"),
            uiLayoutPreferencesStore: UILayoutPreferencesStore(defaults: defaults, key: "layout"),
            logger: AppTestLogger()
        )
    }
}

private final class AppTestTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DualFinderAppTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class AppTestLogger: AppLogging, @unchecked Sendable {
    func log(_ level: LogLevel, _ category: String, _ message: String, metadata: [String: String]) { }
}

private final class AppRecordingCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: URL?
    }

    private let lock = NSLock()
    private var results: [CommandResult]
    private(set) var calls: [Call] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?
    ) throws -> CommandResult {
        lock.lock()
        defer { lock.unlock() }
        calls.append(Call(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
        guard !results.isEmpty else {
            return CommandResult(exitCode: 0, stdout: "", stderr: "")
        }
        return results.removeFirst()
    }

    func containsCall(arguments: [String]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return calls.contains { $0.arguments == arguments }
    }
}
