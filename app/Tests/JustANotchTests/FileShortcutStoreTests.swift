import XCTest
@testable import JustANotch

final class FileShortcutStoreTests: XCTestCase {
    func testFindNodeByPathReturnsNestedCatalogue() {
        let design = Catalogue(name: "Design")
        let work = Catalogue(name: "Work", children: [design])
        let root = Catalogue(name: "", children: [work])

        let found = root.node(atPath: [work.id, design.id])
        XCTAssertEqual(found?.name, "Design")
    }

    func testFindNodeByEmptyPathReturnsSelf() {
        let root = Catalogue(name: "")
        XCTAssertEqual(root.node(atPath: [])?.id, root.id)
    }

    func testInsertChildAtPath() {
        var root = Catalogue(name: "")
        let work = Catalogue(name: "Work")
        root.insert(child: work, atPath: [])
        XCTAssertEqual(root.children.map(\.name), ["Work"])

        let design = Catalogue(name: "Design")
        root.insert(child: design, atPath: [work.id])
        XCTAssertEqual(root.node(atPath: [work.id])?.children.map(\.name), ["Design"])
    }

    func testRemoveCatalogueAtPath() {
        let design = Catalogue(name: "Design")
        var root = Catalogue(name: "", children: [Catalogue(name: "Work", children: [design])])
        let workId = root.children[0].id
        root.removeCatalogue(id: design.id, atParentPath: [workId])
        XCTAssertTrue(root.node(atPath: [workId])!.children.isEmpty)
    }

    func testRenameCatalogueAtPath() {
        var root = Catalogue(name: "", children: [Catalogue(name: "Work")])
        let id = root.children[0].id
        root.rename(catalogueId: id, atParentPath: [], to: "Job")
        XCTAssertEqual(root.children[0].name, "Job")
    }

    func testSaveThenLoadRoundTrips() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shortcuts-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = FileShortcutStore(fileURL: tmp)
        store.root.children.append(Catalogue(name: "Work"))
        store.save()

        let reloaded = FileShortcutStore(fileURL: tmp)
        XCTAssertEqual(reloaded.root.children.map(\.name), ["Work"])
    }

    func testLoadMissingFileGivesEmptyRoot() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID()).json")
        let store = FileShortcutStore(fileURL: missing)
        XCTAssertTrue(store.root.children.isEmpty)
        XCTAssertTrue(store.root.files.isEmpty)
    }

    func testAddCatalogueAutoSaves() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sc-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = FileShortcutStore(fileURL: tmp)
        store.addCatalogue(named: "Work", atPath: [])

        let reloaded = FileShortcutStore(fileURL: tmp)
        XCTAssertEqual(reloaded.root.children.map(\.name), ["Work"])
    }

    func testDeleteCatalogue() {
        let store = FileShortcutStore(fileURL: URL(fileURLWithPath: "/nonexistent-\(UUID()).json"))
        store.addCatalogue(named: "Work", atPath: [])
        let id = store.root.children[0].id
        store.deleteCatalogue(id: id, atParentPath: [])
        XCTAssertTrue(store.root.children.isEmpty)
    }

    func testAddFileFromURLStoresResolvableBookmark() throws {
        let tmpFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("target-\(UUID()).txt")
        try "hi".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let store = FileShortcutStore(fileURL: URL(fileURLWithPath: "/nonexistent-\(UUID()).json"))
        store.addFile(url: tmpFile, atPath: [])

        let file = store.root.files[0]
        XCTAssertEqual(file.name, tmpFile.lastPathComponent)

        let resolved = store.resolveURL(for: file)
        XCTAssertEqual(resolved.resolved?.lastPathComponent, tmpFile.lastPathComponent)
        XCTAssertFalse(resolved.isMissing)
    }

    func testResolveBrokenBookmarkReportsMissing() {
        let store = FileShortcutStore(fileURL: URL(fileURLWithPath: "/nonexistent-\(UUID()).json"))
        let bogus = FileShortcut(name: "gone.txt", bookmark: Data([0x00, 0x01, 0x02]))
        let resolved = store.resolveURL(for: bogus)
        XCTAssertTrue(resolved.isMissing)
    }
}
