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
}
