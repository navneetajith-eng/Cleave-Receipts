import XCTest
@testable import Cleave

final class CleaveModelsTests: XCTestCase {
    func testOnlySupportedCurrenciesRemain() {
        XCTAssertEqual(Currency.allCases.map(\.rawValue), ["USD", "INR", "AED"])
    }

    func testRegionsImplyCurrencyAndSettlementMethod() {
        XCTAssertEqual(AppRegion.unitedStates.currency, .usd)
        XCTAssertEqual(AppRegion.unitedStates.settlementMethod, .venmo)
        XCTAssertEqual(AppRegion.india.currency, .inr)
        XCTAssertEqual(AppRegion.india.settlementMethod, .googlePayUPI)
        XCTAssertEqual(AppRegion.unitedArabEmirates.currency, .aed)
        XCTAssertEqual(AppRegion.unitedArabEmirates.settlementMethod, .aani)
    }

    func testSupportedLegacyCurrenciesMapToRegions() {
        XCTAssertEqual(AppRegion.fromLegacyCurrency("USD"), .unitedStates)
        XCTAssertEqual(AppRegion.fromLegacyCurrency("INR"), .india)
        XCTAssertEqual(AppRegion.fromLegacyCurrency("AED"), .unitedArabEmirates)
        XCTAssertNil(AppRegion.fromLegacyCurrency("EUR"))
    }

    func testVenmoHandoffContainsRecipientAmountAndNote() throws {
        let url = try XCTUnwrap(
            PaymentDeepLinkBuilder.buildVenmoURL(recipient: "cleaver", amount: 12.5, note: "Cleave - Dinner")
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(components.scheme, "venmo")
        XCTAssertEqual(query["txn"], "pay")
        XCTAssertEqual(query["amount"], "12.50")
        XCTAssertEqual(query["note"], "Cleave - Dinner")
        XCTAssertEqual(query["recipients"], "cleaver")
    }

    func testGooglePayUPIHandoffContainsRecipientAndINR() throws {
        let url = try XCTUnwrap(
            PaymentDeepLinkBuilder.buildGooglePayURL(
                upiID: "cleave@upi",
                recipientName: "Cleave User",
                amount: 250,
                note: "Dinner"
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(components.scheme, "gpay")
        XCTAssertEqual(components.host, "upi")
        XCTAssertEqual(components.path, "/pay")
        XCTAssertEqual(query["pa"], "cleave@upi")
        XCTAssertEqual(query["am"], "250.00")
        XCTAssertEqual(query["cu"], "INR")
    }

    func testPaymentDetailsValidationMatchesOnboardingRequirements() {
        XCTAssertTrue(PaymentPreferences.isValidVenmo("@cleave-user"))
        XCTAssertFalse(PaymentPreferences.isValidVenmo("not valid"))
        XCTAssertTrue(PaymentPreferences.isValidUPI("cleave@upi"))
        XCTAssertFalse(PaymentPreferences.isValidUPI("cleave"))
        XCTAssertTrue(PaymentPreferences.isComplete(for: .unitedArabEmirates, venmo: "", upi: ""))
    }

    func testMoneyRoundsOnceIntoMinorUnits() {
        XCTAssertEqual(Money(amount: 10.005, currency: .usd).minorUnits, 1001)
        XCTAssertEqual(Money(minorUnits: 1001, currency: .usd).amount, 10.01, accuracy: 0.0001)
    }

    func testLargestRemainderAllocationAlwaysReconciles() {
        for total in 1...500 {
            let allocation = MoneyAllocator.allocate(
                totalMinorUnits: Int64(total),
                weights: ["a": 1, "b": 2, "c": 3, "d": 7]
            )
            XCTAssertEqual(allocation.values.reduce(0, +), Int64(total))
        }
    }

    func testReceiptCurrencyDoesNotChangeWithSelectedRegion() {
        RegionManager.shared.select(.unitedStates)
        let receipt = RemoteReceipt(
            id: UUID(),
            groupId: UUID(),
            title: "Mumbai",
            adminId: UUID(),
            currencyCode: Currency.inr.rawValue,
            taxAmount: 0,
            tipAmount: 0,
            discountAmount: 0,
            imageUrl: nil,
            createdAt: nil,
            items: []
        )

        XCTAssertEqual(receipt.currency, .inr)
        RegionManager.shared.select(.unitedArabEmirates)
        XCTAssertEqual(receipt.currency, .inr)
        PaymentPreferences.clear()
    }

    func testPaymentPreferencesMinimizeIdentifiersAndClearOnDeletion() {
        PaymentPreferences.save(region: .unitedStates, venmo: "@cleaver", upi: "person@bank")
        XCTAssertEqual(PaymentPreferences.venmoUsername, "cleaver")
        XCTAssertEqual(PaymentPreferences.upiID, "")

        PaymentPreferences.save(region: .india, venmo: "cleaver", upi: "person@bank")
        XCTAssertEqual(PaymentPreferences.venmoUsername, "")
        XCTAssertEqual(PaymentPreferences.upiID, "person@bank")

        PaymentPreferences.clear()
        XCTAssertEqual(PaymentPreferences.venmoUsername, "")
        XCTAssertEqual(PaymentPreferences.upiID, "")
        XCTAssertFalse(PaymentPreferences.needsSync)
    }

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

    func testDemoModeBypassesConfigurationAfterOnboarding() {
        XCTAssertEqual(
            LaunchFlow.destination(
                hasSeenOnboarding: true,
                hasCheckedSession: false,
                hasUser: false,
                isSupabaseConfigured: false,
                isDemoMode: true
            ),
            .app
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
          "currency_code": "AED",
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
        XCTAssertEqual(receipt.currency, .aed)
    }

    func testProductMetricPercentiles() {
        XCTAssertEqual(ProductMetrics.percentile(0.5, values: [100, 400, 200, 300]), 300)
        XCTAssertEqual(ProductMetrics.percentile(0.95, values: [100, 200, 300, 400]), 400)
        XCTAssertNil(ProductMetrics.percentile(0.5, values: []))
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
