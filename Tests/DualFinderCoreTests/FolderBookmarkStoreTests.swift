import Foundation
import Testing
@testable import DualFinderCore

@Suite("FolderBookmarkStore")
struct FolderBookmarkStoreTests {
    @Test("stores favorites before recent folders")
    func storesFavoritesBeforeRecentFolders() {
        let suiteName = "FolderBookmarkStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FolderBookmarkStore(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/first")
        let second = URL(fileURLWithPath: "/tmp/second")
        let favorite = URL(fileURLWithPath: "/tmp/favorite")

        store.recordRecentFolder(first)
        store.recordRecentFolder(second)
        store.addFavorite(favorite)

        #expect(store.entries() == [
            FolderBookmarkEntry(url: favorite, isFavorite: true),
            FolderBookmarkEntry(url: second, isFavorite: false),
            FolderBookmarkEntry(url: first, isFavorite: false)
        ])
    }

    @Test("moving a recent folder to favorites removes the duplicate recent entry")
    func favoriteRemovesDuplicateRecentEntry() {
        let suiteName = "FolderBookmarkStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FolderBookmarkStore(defaults: defaults)
        let folder = URL(fileURLWithPath: "/tmp/folder")

        store.recordRecentFolder(folder)
        store.addFavorite(folder)

        #expect(store.entries() == [
            FolderBookmarkEntry(url: folder, isFavorite: true)
        ])
    }

    @Test("removing a favorite keeps it as a recent folder")
    func removingFavoriteKeepsRecentFolder() {
        let suiteName = "FolderBookmarkStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FolderBookmarkStore(defaults: defaults)
        let folder = URL(fileURLWithPath: "/tmp/folder")

        store.addFavorite(folder)
        store.removeFavorite(folder)

        #expect(store.entries() == [
            FolderBookmarkEntry(url: folder, isFavorite: false)
        ])
    }
}
