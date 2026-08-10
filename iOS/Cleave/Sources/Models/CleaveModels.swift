import Foundation
import UIKit

// MARK: - Remote/domain models

struct Profile: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let email: String
    let username: String?
    let avatarUrl: String?
    let createdAt: String?

    var displayName: String {
        let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? email : trimmed
    }
}

struct InboxItem: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let actorId: UUID?
    let groupId: UUID?
    let kind: String
    let title: String
    let body: String
    var isRead: Bool
    let createdAt: String?
}

struct GroupMemberModel: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var username: String

    var displayName: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Member" : trimmed
    }
}

struct RemoteReceipt: Codable, Identifiable, Equatable {
    let id: UUID
    let groupId: UUID
    var title: String
    let adminId: UUID
    var taxAmount: Double
    var tipAmount: Double
    var discountAmount: Double
    let imageUrl: String?
    let createdAt: String?
    var items: [ReceiptItem]
    var memories: [RemoteMemory]? = nil

    var total: Double {
        items.reduce(0) { $0 + $1.price } + taxAmount + tipAmount - discountAmount
    }
}

struct RemoteMemory: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let receiptId: UUID
    let userId: UUID
    let createdAt: String?
}

struct ReceiptItem: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let price: Double
}

struct RemoteBalance: Codable, Equatable {
    let userId: UUID
    let itemsTotal: Double
    let taxShare: Double
    let tipShare: Double
    let discountShare: Double
    let totalOwed: Double
}

struct ParsedReceiptResponse: Codable, Equatable {
    struct LineItem: Codable, Equatable {
        let description: String
        let price: Double
    }

    let vendorName: String
    let tax: Double
    let tip: Double
    let discount: Double
    let total: Double
    let lineItems: [LineItem]
}

private struct LocalReceiptCollection: Codable {
    let groupID: UUID
    var receipts: [RemoteReceipt]
}

struct ReceiptDraft: Codable, Identifiable, Equatable {
    let id: UUID
    let groupID: UUID
    let imagePath: String
    let createdAt: Date
    var errorMessage: String?
}

// MARK: - Cached app state

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var groups: [GroupModel] = []
    @Published private(set) var localReceipts: [UUID: [RemoteReceipt]] = [:]
    @Published private(set) var receiptDrafts: [ReceiptDraft] = []
    @Published private(set) var isRefreshing = false

    private var activeUserID: UUID?
    private let legacyCacheKey = "cleave.groups.v2"

    init() {
        // Version 2 was not account-scoped and could expose a previous user's cache.
        UserDefaults.standard.removeObject(forKey: legacyCacheKey)
    }

    func refreshGroups() async {
        guard let userID = SupabaseManager.shared.currentUser?.id else { return }
        prepareCache(for: userID)
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let localGroups = groups.filter { !$0.isCollaborative }
            let remoteGroups = try await CleaveAPI.shared.fetchGroups()
            groups = remoteGroups + localGroups.filter { local in
                !remoteGroups.contains(where: { $0.id == local.id })
            }
            saveGroups()
        } catch {
            // Cached and local groups remain fully usable while the network is unavailable.
            print("Group refresh deferred: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createLocalGroup(name: String, memberNames: [String], createdBy: UUID) -> GroupModel {
        let normalizedNames = memberNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        let members = normalizedNames.compactMap { name -> GroupMemberModel? in
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return GroupMemberModel(id: UUID(), username: name)
        }

        let group = GroupModel(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            members: members,
            isCollaborative: false,
            createdBy: createdBy
        )
        replace(with: group)
        return group
    }

    func replace(with group: GroupModel) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.insert(group, at: 0)
        }
        saveGroups()
    }

    func receipts(for groupID: UUID) -> [RemoteReceipt] {
        localReceipts[groupID] ?? []
    }

    func saveLocalReceipt(_ receipt: RemoteReceipt) {
        var receipts = localReceipts[receipt.groupId] ?? []
        if let index = receipts.firstIndex(where: { $0.id == receipt.id }) {
            receipts[index] = receipt
        } else {
            receipts.insert(receipt, at: 0)
        }
        localReceipts[receipt.groupId] = receipts
        saveLocalReceipts()
    }

    func drafts(for groupID: UUID) -> [ReceiptDraft] {
        receiptDrafts.filter { $0.groupID == groupID }
    }

    func stageReceiptImage(_ image: UIImage, groupID: UUID) throws -> ReceiptDraft {
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw CleaveAPI.APIError.invalidResponse
        }
        let directory = try draftDirectory()
        let id = UUID()
        let url = directory.appendingPathComponent("\(id.uuidString).jpg")
        try data.write(to: url, options: .atomic)
        let draft = ReceiptDraft(
            id: id,
            groupID: groupID,
            imagePath: url.path,
            createdAt: Date(),
            errorMessage: nil
        )
        receiptDrafts.insert(draft, at: 0)
        saveReceiptDrafts()
        return draft
    }

    func image(for draft: ReceiptDraft) -> UIImage? {
        UIImage(contentsOfFile: draft.imagePath)
    }

    func markDraftFailed(id: UUID, message: String) {
        guard let index = receiptDrafts.firstIndex(where: { $0.id == id }) else { return }
        receiptDrafts[index].errorMessage = message
        saveReceiptDrafts()
    }

    func removeDraft(id: UUID) {
        guard let draft = receiptDrafts.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(atPath: draft.imagePath)
        receiptDrafts.removeAll { $0.id == id }
        saveReceiptDrafts()
    }

    func updateLocalReceipt(
        id: UUID,
        groupID: UUID,
        title: String,
        items: [ReceiptItem],
        tax: Double,
        tip: Double,
        discount: Double
    ) {
        guard var receipts = localReceipts[groupID],
              let index = receipts.firstIndex(where: { $0.id == id }) else { return }
        receipts[index].title = title
        receipts[index].items = items
        receipts[index].taxAmount = tax
        receipts[index].tipAmount = tip
        receipts[index].discountAmount = discount
        localReceipts[groupID] = receipts
        saveLocalReceipts()
    }

    func renameGroup(id: UUID, newName: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = newName
        saveGroups()
    }

    func deleteGroup(id: UUID) {
        groups.removeAll(where: { $0.id == id })
        localReceipts.removeValue(forKey: id)
        for draft in receiptDrafts where draft.groupID == id {
            try? FileManager.default.removeItem(atPath: draft.imagePath)
        }
        receiptDrafts.removeAll { $0.groupID == id }
        saveGroups()
        saveLocalReceipts()
        saveReceiptDrafts()
    }

    func addMember(to groupID: UUID, member: GroupMemberModel) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if !groups[index].members.contains(where: { $0.id == member.id }) {
            groups[index].members.append(member)
            saveGroups()
        }
    }

    func getGroup(id: UUID) -> GroupModel? {
        groups.first(where: { $0.id == id })
    }

    func clearForSignOut() {
        groups = []
        localReceipts = [:]
        receiptDrafts = []
        activeUserID = nil
    }

    func clearForDeletedAccount(userID: UUID) {
        UserDefaults.standard.removeObject(forKey: cacheKey(for: userID))
        UserDefaults.standard.removeObject(forKey: localReceiptCacheKey(for: userID))
        UserDefaults.standard.removeObject(forKey: receiptDraftCacheKey(for: userID))
        for draft in receiptDrafts {
            try? FileManager.default.removeItem(atPath: draft.imagePath)
        }
        groups = []
        localReceipts = [:]
        receiptDrafts = []
        activeUserID = nil
    }

    private func saveGroups() {
        guard let activeUserID else { return }
        guard let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: activeUserID))
    }

    private func saveLocalReceipts() {
        guard let activeUserID else { return }
        let collections = localReceipts.map {
            LocalReceiptCollection(groupID: $0.key, receipts: $0.value)
        }
        guard let data = try? JSONEncoder().encode(collections) else { return }
        UserDefaults.standard.set(data, forKey: localReceiptCacheKey(for: activeUserID))
    }

    private func saveReceiptDrafts() {
        guard let activeUserID,
              let data = try? JSONEncoder().encode(receiptDrafts) else { return }
        UserDefaults.standard.set(data, forKey: receiptDraftCacheKey(for: activeUserID))
    }

    private func prepareCache(for userID: UUID) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: userID)),
              let saved = try? JSONDecoder().decode([GroupModel].self, from: data) else {
            groups = []
            loadLocalReceipts(for: userID)
            loadReceiptDrafts(for: userID)
            return
        }
        groups = saved
        loadLocalReceipts(for: userID)
        loadReceiptDrafts(for: userID)
    }

    private func cacheKey(for userID: UUID) -> String {
        "cleave.groups.v3.\(userID.uuidString.lowercased())"
    }


    private func localReceiptCacheKey(for userID: UUID) -> String {
        "cleave.local-receipts.v1.\(userID.uuidString.lowercased())"
    }

    private func receiptDraftCacheKey(for userID: UUID) -> String {
        "cleave.receipt-drafts.v1.\(userID.uuidString.lowercased())"
    }

    private func loadLocalReceipts(for userID: UUID) {
        guard let data = UserDefaults.standard.data(forKey: localReceiptCacheKey(for: userID)),
              let collections = try? JSONDecoder().decode([LocalReceiptCollection].self, from: data) else {
            localReceipts = [:]
            return
        }
        localReceipts = Dictionary(uniqueKeysWithValues: collections.map { ($0.groupID, $0.receipts) })
    }

    private func loadReceiptDrafts(for userID: UUID) {
        guard let data = UserDefaults.standard.data(forKey: receiptDraftCacheKey(for: userID)),
              let drafts = try? JSONDecoder().decode([ReceiptDraft].self, from: data) else {
            receiptDrafts = []
            return
        }
        receiptDrafts = drafts.filter { FileManager.default.fileExists(atPath: $0.imagePath) }
    }

    private func draftDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("CleaveReceiptDrafts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

struct GroupModel: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var members: [GroupMemberModel]
    var isCollaborative: Bool
    var createdBy: UUID

    init(
        id: UUID,
        name: String,
        members: [GroupMemberModel],
        isCollaborative: Bool,
        createdBy: UUID
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.isCollaborative = isCollaborative
        self.createdBy = createdBy
    }
}
