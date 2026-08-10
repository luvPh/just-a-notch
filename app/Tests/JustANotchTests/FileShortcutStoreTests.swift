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
}
