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
        XCTAssertTrue(PaymentPreferences.isValidAani("+971501234567"))
        XCTAssertFalse(PaymentPreferences.isValidAani("not valid"))
        XCTAssertTrue(PaymentPreferences.isComplete(for: .unitedArabEmirates, venmo: "", upi: ""))
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

    func testReplayOnboardingRestoresSessionBeforeShowingWalkthrough() {
        XCTAssertEqual(
            LaunchFlow.destination(
                hasSeenOnboarding: true,
                hasCheckedSession: false,
                hasUser: false,
                isSupabaseConfigured: true,
                isReplayingOnboarding: true
            ),
            .sessionLoading
        )
        XCTAssertEqual(
            LaunchFlow.destination(
                hasSeenOnboarding: true,
                hasCheckedSession: true,
                hasUser: true,
                isSupabaseConfigured: true,
                isReplayingOnboarding: true
            ),
            .onboarding
        )
        XCTAssertEqual(
            LaunchFlow.destination(
                hasSeenOnboarding: true,
                hasCheckedSession: true,
                hasUser: true,
                isSupabaseConfigured: true
            ),
            .app
        )
    }

    func testReplayOnboardingContainsTutorialOnly() {
        XCTAssertEqual(OnboardingFlow.steps(isReplay: true), [0, 1, 5])
        XCTAssertFalse(OnboardingFlow.steps(isReplay: true).contains(2), "Replay must not ask for region again")
        XCTAssertFalse(OnboardingFlow.steps(isReplay: true).contains(3), "Replay must not ask for payment again")
        XCTAssertFalse(OnboardingFlow.steps(isReplay: true).contains(4), "Replay must not ask for age again")
        XCTAssertEqual(OnboardingFlow.steps(isReplay: false), [0, 1, 2, 3, 4, 5])
    }

    func testReceiptScanRecoveryExplainsServiceMismatch() {
        XCTAssertTrue(
            ReceiptScanRecovery.message(for: CleaveAPI.APIError.serviceUpdateRequired)
                .localizedCaseInsensitiveContains("service needs an update")
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
        XCTAssertNotEqual(before.preferredName, after.preferredName)
    }

    func testDisplayNameIsPreferredWithoutChangingStableUsername() {
        let member = GroupMemberModel(
            id: UUID(),
            username: "navneet.ajith",
            displayName: "Nav"
        )

        XCTAssertEqual(member.preferredName, "Nav")
        XCTAssertEqual(member.username, "navneet.ajith")
    }

    func testReceiptCurrencyDecodesIndependentlyFromUserRegion() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "group_id": "\(UUID().uuidString)",
          "title": "Dubai lunch",
          "admin_id": "\(UUID().uuidString)",
          "currency_code": "AED",
          "tax_amount": 0,
          "tip_amount": 0,
          "discount_amount": 0,
          "items": []
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let receipt = try decoder.decode(RemoteReceipt.self, from: Data(json.utf8))

        XCTAssertEqual(receipt.currency, .aed)
    }

    func testParsedReceiptCurrencyDecodesFromScannerResponse() throws {
        let json = """
        {
          "vendor_name": "Dubai lunch",
          "currency_code": "AED",
          "tax": 2.5,
          "tip": 0,
          "discount": 0,
          "total": 22.5,
          "line_items": [
            { "description": "Burger", "price": 20 }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let receipt = try decoder.decode(ParsedReceiptResponse.self, from: Data(json.utf8))

        XCTAssertEqual(receipt.currencyCode, .aed)
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

    func testReceiptDecodesSavedAssignmentsForReview() throws {
        let receiptID = UUID()
        let assignedUserID = UUID()
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
          "items": [{
            "id": "item-1",
            "name": "Coffee",
            "price": 5,
            "assigned_user_ids": ["\(assignedUserID.uuidString)"]
          }],
          "memories": []
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let receipt = try decoder.decode(RemoteReceipt.self, from: Data(json.utf8))

        XCTAssertEqual(receipt.items[0].assignedUserIds, [assignedUserID])
        XCTAssertEqual(receipt.assignmentMap["item-1"], Set([assignedUserID.uuidString]))
    }

    func testReceiptDecodesParticipantProgressAndGroupExperiences() throws {
        let receiptID = UUID()
        let userID = UUID()
        let json = """
        {
          "id": "\(receiptID.uuidString)",
          "group_id": "\(UUID().uuidString)",
          "title": "Dinner",
          "admin_id": "\(userID.uuidString)",
          "tax_amount": 0,
          "tip_amount": 0,
          "discount_amount": 0,
          "image_url": null,
          "created_at": null,
          "items": [],
          "memories": [],
          "participants": [{
            "receipt_id": "\(receiptID.uuidString)",
            "user_id": "\(userID.uuidString)",
            "status": "submitted",
            "submitted_at": "2026-08-14T00:00:00Z"
          }],
          "experiences": [{
            "receipt_id": "\(receiptID.uuidString)",
            "user_id": "\(userID.uuidString)",
            "rating": 5,
            "created_at": null,
            "updated_at": null
          }]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let receipt = try decoder.decode(RemoteReceipt.self, from: Data(json.utf8))

        XCTAssertEqual(receipt.participants?.first?.hasSubmitted, true)
        XCTAssertEqual(receipt.experiences?.first?.rating, 5)
    }

    func testBalanceDecodesExactPerItemShares() throws {
        let userID = UUID()
        let json = """
        {
          "user_id": "\(userID.uuidString)",
          "items": [{"item_id": "fries", "name": "Shared fries", "amount": 4.01}],
          "items_total": 4.01,
          "tax_share": 0.40,
          "tip_share": 0.20,
          "discount_share": 0.10,
          "total_owed": 4.51
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let balance = try decoder.decode(RemoteBalance.self, from: Data(json.utf8))

        XCTAssertEqual(balance.items.first?.name, "Shared fries")
        XCTAssertEqual(balance.items.first?.amount ?? 0, 4.01, accuracy: 0.001)
        XCTAssertEqual(balance.totalOwed, 4.51, accuracy: 0.001)
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
