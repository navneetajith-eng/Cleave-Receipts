import XCTest
@testable import Cleave

final class CleaveModelsTests: XCTestCase {
    func testFirstLaunchAlwaysRoutesToOnboarding() {
        XCTAssertEqual(
            LaunchFlow.destination(
                hasSeenOnboarding: false,
                hasCheckedSession: true,
                hasUser: false,
                isSupabaseConfigured: false
            ),
            .onboarding
        )
    }

    func testMissingSupabaseConfigurationIsShownBeforeAuthentication() {
        XCTAssertEqual(
            LaunchFlow.destination(
                hasSeenOnboarding: true,
                hasCheckedSession: true,
                hasUser: false,
                isSupabaseConfigured: false
            ),
            .configurationRequired
        )
    }

    func testConfiguredSignedOutLaunchRoutesToAuthentication() {
        XCTAssertEqual(
            LaunchFlow.destination(
                hasSeenOnboarding: true,
                hasCheckedSession: true,
                hasUser: false,
                isSupabaseConfigured: true
            ),
            .authentication
        )
    }

    func testReceiptTotalIncludesAdjustments() {
        let receipt = RemoteReceipt(
            id: UUID(),
            groupId: UUID(),
            title: "Cafe",
            adminId: UUID(),
            taxAmount: 1.5,
            tipAmount: 2,
            discountAmount: 1,
            imageUrl: nil,
            createdAt: nil,
            items: [ReceiptItem(id: "item", name: "Coffee", price: 5)]
        )

        XCTAssertEqual(receipt.total, 7.5, accuracy: 0.001)
    }

    func testMemberIdentityDoesNotDependOnUsername() {
        let id = UUID()
        let before = GroupMemberModel(id: id, username: "old_name")
        let after = GroupMemberModel(id: id, username: "new_name")

        XCTAssertEqual(before.id, after.id)
        XCTAssertNotEqual(before.displayName, after.displayName)
    }

    func testReceiptDecodesPrivateMemoryMetadata() throws {
        let receiptID = UUID()
        let memoryID = UUID()
        let userID = UUID()
        let json = """
        {
          "id": "\(receiptID.uuidString)",
          "group_id": "\(UUID().uuidString)",
          "title": "Cafe",
          "admin_id": "\(UUID().uuidString)",
          "tax_amount": 0,
          "tip_amount": 0,
          "discount_amount": 0,
          "image_url": null,
          "created_at": null,
          "items": [],
          "memories": [{
            "id": "\(memoryID.uuidString)",
            "receipt_id": "\(receiptID.uuidString)",
            "user_id": "\(userID.uuidString)",
            "created_at": null
          }]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let receipt = try decoder.decode(RemoteReceipt.self, from: Data(json.utf8))

        XCTAssertEqual(receipt.memories?.first?.id, memoryID)
        XCTAssertEqual(receipt.memories?.first?.userId, userID)
    }

    func testProductMetricPercentiles() {
        XCTAssertEqual(ProductMetrics.percentile(0.5, values: [100, 400, 200, 300]), 300)
        XCTAssertEqual(ProductMetrics.percentile(0.95, values: [100, 200, 300, 400]), 400)
        XCTAssertNil(ProductMetrics.percentile(0.5, values: []))
    }

    func testPasswordPolicyRequiresLengthLetterAndNumber() {
        XCTAssertNotNil(PasswordPolicy.validationMessage(for: "short1"))
        XCTAssertNotNil(PasswordPolicy.validationMessage(for: "onlyletters"))
        XCTAssertNotNil(PasswordPolicy.validationMessage(for: "12345678"))
        XCTAssertNil(PasswordPolicy.validationMessage(for: "cleave2026"))
    }

    func testOnlyCleaveAuthCallbackIsAccepted() {
        XCTAssertTrue(SupabaseManager.isAuthCallback(URL(string: "cleave://auth-callback?code=abc")!))
        XCTAssertFalse(SupabaseManager.isAuthCallback(URL(string: "cleave://unexpected?code=abc")!))
        XCTAssertFalse(SupabaseManager.isAuthCallback(URL(string: "https://example.com/auth-callback")!))
    }

    @MainActor
    func testDeletedAccountClearsAccountScopedCache() {
        let userID = UUID()
        let key = "cleave.groups.v3.\(userID.uuidString.lowercased())"
        UserDefaults.standard.set(Data("cached".utf8), forKey: key)

        AppStore().clearForDeletedAccount(userID: userID)

        XCTAssertNil(UserDefaults.standard.data(forKey: key))
    }
}
