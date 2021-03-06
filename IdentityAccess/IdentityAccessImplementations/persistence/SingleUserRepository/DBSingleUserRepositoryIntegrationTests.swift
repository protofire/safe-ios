//
//  Copyright © 2018 Gnosis Ltd. All rights reserved.
//

import XCTest
@testable import IdentityAccessImplementations
import IdentityAccessDomainModel
import Database

class DBSingleUserRepositoryIntegrationTests: XCTestCase {

    func test_database() throws {
        let db = SQLiteDatabase(name: "DBSingleUserRepositoryIntegrationTests",
                                fileManager: FileManager.default,
                                sqlite: CSQLite3(),
                                bundleId: "IdentityAccessImplementationsTests")
        try? db.destroy() // protects from corrupted state
        try db.create()
        defer { try? db.destroy() }
        let repo = DBSingleUserRepository(db: db)
        repo.setUp()
        let user = User(id: repo.nextId(), password: "MyPassword1")
        repo.save(user)
        XCTAssertEqual(repo.primaryUser(), user)
        XCTAssertEqual(repo.user(encryptedPassword: "MyPassword1"), user)
        repo.remove(user)
        XCTAssertNil(repo.primaryUser())
    }

}
