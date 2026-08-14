import Foundation
import UIKit

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

final class CleaveAPI {
    static let shared = CleaveAPI()

    enum APIError: LocalizedError {
        case configuration
        case invalidResponse
        case unauthorized
        case serviceUpdateRequired
        case server(status: Int, message: String)
        case decoding

        var errorDescription: String? {
            switch self {
            case .configuration:
                return "The Cleave service URL is not configured."
            case .invalidResponse:
                return "The server returned an invalid response."
            case .unauthorized:
                return "Your session has expired. Please sign in again."
            case .serviceUpdateRequired:
                return "Cleave's beta service needs to be updated before this feature can sync."
            case .server(_, let message):
                return message
            case .decoding:
                return "Cleave couldn't understand the server response."
            }
        }
    }

    private struct ErrorEnvelope: Decodable { let detail: String? }
    private struct EmptyResponse: Decodable {}
    private struct GroupPayload: Encodable {
        let name: String
        let isCollaborative: Bool
        let memberIds: [String]
    }
    private struct GroupUpdatePayload: Encodable { let name: String }
    private struct MemberPayload: Encodable { let userId: String }
    private struct ProfilePayload: Encodable {
        let username: String
        let displayName: String?
        let email: String
        let ageBand: String?
    }
    private struct ProfileUpdatePayload: Encodable {
        let username: String?
        let displayName: String?
        let ageBand: String?
        let avatarVisibility: String?
        let paymentVisibility: String?
    }
    private struct PaymentDetailsPayload: Encodable {
        let regionCode: String
        let venmoUsername: String?
        let upiId: String?
        let aaniId: String?
    }
    private struct ProfileSettingsPayload: Encodable {
        let profile: ProfileUpdatePayload
        let paymentDetails: PaymentDetailsPayload
    }
    struct Capabilities: Decodable, Equatable {
        let apiVersion: Int
        let features: [String]
    }
    private struct ExperiencePayload: Encodable { let rating: Int }
    private struct PaymentReviewPayload: Encodable { let status: String }
    private struct AssignmentPayload: Encodable { let userIds: [String] }
    private struct AssignmentBatchPayload: Encodable {
        struct Item: Encodable {
            let itemId: String
            let userIds: [String]
        }
        let items: [Item]
    }
    private struct ManualReceiptPayload: Encodable {
        struct Item: Encodable { let name: String; let price: Double }
        let title: String
        let currencyCode: String
        let taxAmount: Double
        let tipAmount: Double
        let discountAmount: Double
        let items: [Item]
    }
    private struct ReceiptUpdatePayload: Encodable {
        struct Item: Encodable {
            let id: String
            let name: String
            let price: Double
        }
        let title: String
        let currencyCode: String
        let taxAmount: Double
        let tipAmount: Double
        let discountAmount: Double
        let items: [Item]
    }
    private struct AdminReceiptReviewPayload: Encodable {
        let receipt: ReceiptUpdatePayload
        let assignments: AssignmentBatchPayload
    }
    private struct ReceiptClaimPayload: Encodable {
        let itemIds: [String]
        let receipt: ReceiptUpdatePayload?
    }
    private struct GroupResponse: Decodable {
        struct MemberResponse: Decodable {
            let id: UUID
            let username: String
            let displayName: String?
            let regionCode: String?
            let venmoUsername: String?
            let upiId: String?
            let aaniId: String?
        }
        let id: UUID
        let name: String
        let createdBy: UUID
        let isCollaborative: Bool
        let members: [MemberResponse]

        var model: GroupModel {
            GroupModel(
                id: id,
                name: name,
                members: members.map {
                    GroupMemberModel(
                        id: $0.id,
                        username: $0.username,
                        displayName: $0.displayName,
                        regionCode: $0.regionCode,
                        venmoUsername: $0.venmoUsername,
                        upiId: $0.upiId,
                        aaniId: $0.aaniId
                    )
                },
                isCollaborative: isCollaborative,
                createdBy: createdBy
            )
        }
    }

    func fetchGroups() async throws -> [GroupModel] {
        let response: [GroupResponse] = try await send(path: "groups")
        return response.map(\.model)
    }

    func createGroup(name: String, isCollaborative: Bool, memberIDs: [UUID]) async throws -> GroupModel {
        let payload = GroupPayload(
            name: name,
            isCollaborative: isCollaborative,
            memberIds: memberIDs.map(\.uuidString)
        )
        let response: GroupResponse = try await send(path: "groups", method: "POST", body: payload)
        return response.model
    }

    func renameGroup(id: UUID, name: String) async throws -> GroupModel {
        let response: GroupResponse = try await send(
            path: "groups/\(id.uuidString)",
            method: "PATCH",
            body: GroupUpdatePayload(name: name)
        )
        return response.model
    }

    func leaveGroup(id: UUID) async throws {
        let _: Data = try await sendData(path: "groups/\(id.uuidString)/leave", method: "POST")
    }

    func addMember(groupID: UUID, profileID: UUID) async throws -> GroupModel {
        let response: GroupResponse = try await send(
            path: "groups/\(groupID.uuidString)/members",
            method: "POST",
            body: MemberPayload(userId: profileID.uuidString)
        )
        return response.model
    }

    func searchProfiles(query: String) async throws -> [Profile] {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        let queryString = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await send(path: "profiles\(queryString)")
    }

    func bootstrapProfile(username: String, email: String, ageBand: AgeBand? = nil) async throws -> Profile {
        try await send(
            path: "profiles/bootstrap",
            method: "POST",
            body: ProfilePayload(username: username, displayName: username, email: email, ageBand: ageBand?.rawValue)
        )
    }

    func fetchCurrentProfile() async throws -> Profile {
        try await send(path: "profiles/me")
    }

    func updateProfile(
        username: String? = nil,
        displayName: String? = nil,
        ageBand: AgeBand? = nil,
        avatarVisibility: ProfileVisibility? = nil,
        paymentVisibility: ProfileVisibility? = nil
    ) async throws -> Profile {
        try await send(
            path: "profiles/me",
            method: "PATCH",
            body: ProfileUpdatePayload(
                username: username,
                displayName: displayName,
                ageBand: ageBand?.rawValue,
                avatarVisibility: avatarVisibility?.rawValue,
                paymentVisibility: paymentVisibility?.rawValue
            )
        )
    }

    func updatePaymentDetails(
        region: AppRegion,
        venmoUsername: String,
        upiID: String,
        aaniID: String = ""
    ) async throws -> Profile {
        try await send(
            path: "profiles/me/payment-details",
            method: "PATCH",
            body: PaymentDetailsPayload(
                regionCode: region.rawValue,
                venmoUsername: PaymentPreferences.normalizedVenmo(venmoUsername).nilIfEmpty,
                upiId: PaymentPreferences.normalizedUPI(upiID).nilIfEmpty,
                aaniId: PaymentPreferences.normalizedAani(aaniID).nilIfEmpty
            )
        )
    }

    func updateProfileSettings(
        username: String,
        displayName: String,
        ageBand: AgeBand,
        avatarVisibility: ProfileVisibility,
        paymentVisibility: ProfileVisibility,
        region: AppRegion,
        venmoUsername: String,
        upiID: String,
        aaniID: String
    ) async throws -> Profile {
        do {
            return try await send(
                path: "profiles/me/settings",
                method: "PUT",
                body: ProfileSettingsPayload(
                    profile: ProfileUpdatePayload(
                        username: username,
                        displayName: displayName,
                        ageBand: ageBand.rawValue,
                        avatarVisibility: avatarVisibility.rawValue,
                        paymentVisibility: paymentVisibility.rawValue
                    ),
                    paymentDetails: PaymentDetailsPayload(
                        regionCode: region.rawValue,
                        venmoUsername: PaymentPreferences.normalizedVenmo(venmoUsername).nilIfEmpty,
                        upiId: PaymentPreferences.normalizedUPI(upiID).nilIfEmpty,
                        aaniId: PaymentPreferences.normalizedAani(aaniID).nilIfEmpty
                    )
                )
            )
        } catch APIError.server(let status, _) where status == 404 {
            throw APIError.serviceUpdateRequired
        }
    }

    func fetchCapabilities() async throws -> Capabilities {
        do {
            return try await send(path: "capabilities")
        } catch APIError.server(let status, _) where status == 404 {
            throw APIError.serviceUpdateRequired
        }
    }

    func updateProfileAvatar(image: UIImage) async throws -> Profile {
        guard let imageData = image.jpegData(compressionQuality: 0.82) else {
            throw APIError.invalidResponse
        }
        return try await upload(path: "profiles/me/avatar", data: imageData, filename: "avatar.jpg")
    }

    func fetchProfileAvatar(profileID: UUID) async throws -> Data {
        try await sendData(path: "profiles/\(profileID.uuidString)/avatar")
    }

    func fetchFriends() async throws -> [Profile] {
        try await send(path: "friends")
    }

    func fetchFriendProfile(id: UUID) async throws -> Profile {
        try await send(path: "friends/\(id.uuidString)")
    }

    func fetchInbox() async throws -> [InboxItem] {
        try await send(path: "inbox")
    }

    func markInboxItemRead(id: UUID) async throws -> InboxItem {
        let body = Data("{}".utf8)
        let data = try await sendData(
            path: "inbox/\(id.uuidString)/read",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        return try decode(InboxItem.self, from: data)
    }

    func deleteAccount() async throws {
        let _: Data = try await sendData(path: "profiles/me", method: "DELETE")
    }

    func fetchReceipts(groupID: UUID) async throws -> [RemoteReceipt] {
        try await send(path: "groups/\(groupID.uuidString)/receipts")
    }

    func createManualReceipt(
        groupID: UUID,
        title: String,
        items: [ReceiptItem],
        tax: Double,
        tip: Double,
        discount: Double,
        currency: Currency
    ) async throws -> RemoteReceipt {
        let payload = ManualReceiptPayload(
            title: title,
            currencyCode: currency.rawValue,
            taxAmount: tax,
            tipAmount: tip,
            discountAmount: discount,
            items: items.map { .init(name: $0.name, price: $0.price) }
        )
        return try await send(
            path: "groups/\(groupID.uuidString)/receipts/manual",
            method: "POST",
            body: payload
        )
    }

    func uploadReceiptImage(image: UIImage, groupID: UUID, requestID: UUID) async throws -> RemoteReceipt {
        guard let imageData = image.jpegData(compressionQuality: 0.82) else {
            throw APIError.invalidResponse
        }
        return try await upload(
            path: "receipts?group_id=\(groupID.uuidString)",
            data: imageData,
            filename: "receipt.jpg",
            idempotencyKey: requestID.uuidString
        )
    }

    func parseReceiptImage(image: UIImage) async throws -> ParsedReceiptResponse {
        guard let imageData = image.jpegData(compressionQuality: 0.82) else {
            throw APIError.invalidResponse
        }
        return try await upload(path: "receipts/parse", data: imageData, filename: "receipt.jpg")
    }

    func uploadMemoryPhoto(data: Data, receiptID: String) async throws -> RemoteMemory {
        try await upload(
            path: "receipts/\(receiptID)/memories",
            data: data,
            filename: "memory.jpg"
        )
    }

    func fetchMemoryPhoto(receiptID: UUID, memoryID: UUID) async throws -> Data {
        try await sendData(
            path: "receipts/\(receiptID.uuidString)/memories/\(memoryID.uuidString)/content"
        )
    }

    func saveExperience(receiptID: String, rating: Int) async throws {
        let _: ReceiptExperienceResponse = try await send(
            path: "receipts/\(receiptID)/experience",
            method: "PUT",
            body: ExperiencePayload(rating: rating)
        )
    }

    func fetchExperienceRating(receiptID: String) async throws -> Int? {
        let response: ReceiptExperienceResponse? = try await send(
            path: "receipts/\(receiptID)/experience"
        )
        return response?.rating
    }

    func updateReceipt(
        receiptID: String,
        title: String,
        items: [ReceiptItem],
        tax: Double,
        tip: Double,
        discount: Double,
        currency: Currency
    ) async throws -> RemoteReceipt {
        let payload = ReceiptUpdatePayload(
            title: title,
            currencyCode: currency.rawValue,
            taxAmount: tax,
            tipAmount: tip,
            discountAmount: discount,
            items: items.map { .init(id: $0.id, name: $0.name, price: $0.price) }
        )
        return try await send(
            path: "receipts/\(receiptID)",
            method: "PATCH",
            body: payload
        )
    }

    func saveAdminReceiptReview(
        receiptID: String,
        title: String,
        items: [ReceiptItem],
        assignments: [String: Set<String>],
        tax: Double,
        tip: Double,
        discount: Double,
        currency: Currency
    ) async throws -> RemoteReceipt {
        let receipt = ReceiptUpdatePayload(
            title: title,
            currencyCode: currency.rawValue,
            taxAmount: tax,
            tipAmount: tip,
            discountAmount: discount,
            items: items.map { .init(id: $0.id, name: $0.name, price: $0.price) }
        )
        let assignmentPayload = AssignmentBatchPayload(
            items: items.map { item in
                .init(itemId: item.id, userIds: Array(assignments[item.id] ?? []).sorted())
            }
        )
        do {
            return try await send(
                path: "receipts/\(receiptID)/review",
                method: "PUT",
                body: AdminReceiptReviewPayload(receipt: receipt, assignments: assignmentPayload)
            )
        } catch APIError.server(let status, _) where status == 404 {
            throw APIError.serviceUpdateRequired
        }
    }

    func submitReceiptClaim(
        receiptID: String,
        itemIDs: [String],
        editedTitle: String? = nil,
        editedItems: [ReceiptItem]? = nil,
        tax: Double? = nil,
        tip: Double? = nil,
        discount: Double? = nil,
        currency: Currency? = nil
    ) async throws -> ReceiptReview {
        let editedReceipt: ReceiptUpdatePayload?
        if let editedTitle, let editedItems, let tax, let tip, let discount, let currency {
            editedReceipt = ReceiptUpdatePayload(
                title: editedTitle,
                currencyCode: currency.rawValue,
                taxAmount: tax,
                tipAmount: tip,
                discountAmount: discount,
                items: editedItems.map { .init(id: $0.id, name: $0.name, price: $0.price) }
            )
        } else {
            editedReceipt = nil
        }
        return try await send(
            path: "receipts/\(receiptID)/claim",
            method: "PUT",
            body: ReceiptClaimPayload(itemIds: itemIDs.sorted(), receipt: editedReceipt)
        )
    }

    func deleteReceipt(receiptID: UUID) async throws {
        let _: Data = try await sendData(path: "receipts/\(receiptID.uuidString)", method: "DELETE")
    }

    func assignItems(receiptID: String, assignments: [String: Set<String>]) async throws {
        let payload = AssignmentBatchPayload(
            items: assignments.map { itemID, userIDs in
                .init(itemId: itemID, userIds: Array(userIDs).sorted())
            }.sorted { $0.itemId < $1.itemId }
        )
        let _: EmptyResponse = try await send(
            path: "receipts/\(receiptID)/assignments",
            method: "PATCH",
            body: payload
        )
    }

    func assignItem(receiptID: String, itemID: String, userIDs: [String]) async throws {
        let _: EmptyResponse = try await send(
            path: "receipts/\(receiptID)/items/\(itemID)/assignments",
            method: "PATCH",
            body: AssignmentPayload(userIds: userIDs)
        )
    }

    func fetchBalances(receiptID: String) async throws -> [RemoteBalance] {
        try await send(path: "receipts/\(receiptID)/balances")
    }

    func fetchReceiptReview(receiptID: String) async throws -> ReceiptReview {
        do {
            return try await send(path: "receipts/\(receiptID)/review")
        } catch APIError.server(let status, _) where status == 404 {
            throw APIError.serviceUpdateRequired
        }
    }

    func markReceiptPaid(receiptID: String) async throws -> RemoteSettlement {
        let body = Data("{}".utf8)
        let data: Data
        do {
            data = try await sendData(
                path: "receipts/\(receiptID)/payment-status",
                method: "PUT",
                body: body,
                contentType: "application/json"
            )
        } catch APIError.server(let status, _) where status == 404 {
            throw APIError.serviceUpdateRequired
        }
        return try decode(RemoteSettlement.self, from: data)
    }

    func withdrawReceiptPaidMark(receiptID: String) async throws {
        do {
            let _: Data = try await sendData(
                path: "receipts/\(receiptID)/payment-status",
                method: "DELETE"
            )
        } catch APIError.server(let status, _) where status == 404 {
            throw APIError.serviceUpdateRequired
        }
    }

    func reviewPayment(receiptID: String, paymentID: UUID, status: String) async throws -> RemoteSettlement {
        do {
            return try await send(
                path: "receipts/\(receiptID)/payments/\(paymentID.uuidString)",
                method: "PATCH",
                body: PaymentReviewPayload(status: status)
            )
        } catch APIError.server(let code, _) where code == 404 {
            throw APIError.serviceUpdateRequired
        }
    }

    private struct ReceiptExperienceResponse: Decodable {
        let receiptId: UUID
        let userId: UUID
        let rating: Int
    }

    private func send<Response: Decodable>(path: String) async throws -> Response {
        let data: Data = try await sendData(path: path)
        return try decode(Response.self, from: data)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        let bodyData = try encoder.encode(body)
        let data: Data = try await sendData(
            path: path,
            method: method,
            body: bodyData,
            contentType: "application/json"
        )
        if Response.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! Response
        }
        return try decode(Response.self, from: data)
    }

    private func sendData(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        guard let baseURL = AppConfiguration.apiBaseURL,
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.configuration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.setValue("Bearer \(try await SupabaseManager.shared.accessToken())", forHTTPHeaderField: "Authorization")
        return try await execute(request)
    }

    private func upload<Response: Decodable>(
        path: String,
        data: Data,
        filename: String,
        idempotencyKey: String? = nil
    ) async throws -> Response {
        guard let baseURL = AppConfiguration.apiBaseURL,
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.configuration
        }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await SupabaseManager.shared.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        return try decode(Response.self, from: await execute(request))
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        let canRetry = method == "GET" || method == "HEAD" || request.value(forHTTPHeaderField: "Idempotency-Key") != nil
        let retryableStatuses = [429, 502, 503, 504]

        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                if canRetry, retryableStatuses.contains(http.statusCode), attempt < 2 {
                    try await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
                    continue
                }
                guard (200...299).contains(http.statusCode) else {
                    if http.statusCode == 401 { throw APIError.unauthorized }
                    let detail = (try? decoder.decode(ErrorEnvelope.self, from: data).detail)
                    throw APIError.server(status: http.statusCode, message: detail ?? "The request failed. Please try again.")
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where canRetry && attempt < 2 {
                if error.code == .cancelled { throw error }
                try await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
            }
        }
        throw APIError.invalidResponse
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do { return try decoder.decode(type, from: data) }
        catch { throw APIError.decoding }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
