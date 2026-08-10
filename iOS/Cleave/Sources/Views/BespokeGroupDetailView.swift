import SwiftUI

struct BespokeGroupDetailView: View {
    let groupId: UUID
    let color: Color
    @Binding var appState: AppState
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore

    @State private var remoteReceipts: [RemoteReceipt] = []
    @State private var isLoadingReceipts: Bool = false
    @State private var showingCollabSearch: Bool = false
    @State private var showingManualEntry: Bool = false
    @State private var selectedMemberSearchResults: [Profile] = []
    @State private var retryingDraftIDs: Set<UUID> = []

    @ObservedObject private var supabase = SupabaseManager.shared

    var group: GroupModel? {
        store.getGroup(id: groupId)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Expanded Background
            color
                .matchedGeometryEffect(id: "groupBackground-\(groupId)", in: namespace)
                .clipShape(ReceiptCardShape())
                .shadow(color: Color.black.opacity(0.3), radius: 20, y: 15)
                .ignoresSafeArea(edges: .bottom)

            if let group = group {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                appState = .home
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Color.white.opacity(0.8))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 60)

                    Text(group.name)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)

                    Text("\(group.members.count) members")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.8))
                        .padding(.horizontal, 30)

                    // Horizontal scroll of members
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(group.members) { member in
                                VStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(width: 60, height: 60)
                                        .overlay(
                                            Text(String(member.displayName.prefix(1)))
                                                .font(.system(size: 24, design: .serif))
                                                .foregroundColor(.white)
                                        )
                                    Text(member.displayName)
                                        .font(.caption)
                                        .foregroundColor(Color.white.opacity(0.9))
                                }
                            }

                            if group.isCollaborative && group.createdBy == supabase.currentUser?.id {
                                Button(action: {
                                    showingCollabSearch = true
                                }) {
                                    VStack {
                                        Circle()
                                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                            .foregroundColor(Color.white.opacity(0.5))
                                            .frame(width: 60, height: 60)
                                            .overlay(
                                                Image(systemName: "plus")
                                                    .foregroundColor(Color.white.opacity(0.8))
                                            )
                                        Text("Add")
                                            .font(.caption)
                                            .foregroundColor(Color.white.opacity(0.7))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 30)
                    }
                    .frame(height: 100)

                    Spacer()

                    // Action Area
                    VStack(spacing: 30) {
                        if !store.drafts(for: groupId).isEmpty {
                            VStack(spacing: 12) {
                                ForEach(store.drafts(for: groupId)) { draft in
                                    receiptDraftCard(draft)
                                }
                            }
                        }

                        if isLoadingReceipts {
                            VStack(spacing: 16) {
                                ForEach(0..<3, id: \.self) { _ in
                                    ReceiptSkeletonView()
                                }
                            }
                        } else if remoteReceipts.isEmpty {
                            EmptyStateView(
                                iconName: "doc.text.magnifyingglass",
                                title: "No Receipts",
                                message: "Scan your first receipt to start splitting."
                            )
                            .padding(.top, 40)
                        } else {
                            VStack(spacing: 16) {
                                ForEach(remoteReceipts) { receipt in
                                    remoteReceiptCard(receipt: receipt)
                                }
                            }
                        }

                        Button(action: {
                            HapticsManager.shared.playImpact(style: .medium)
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                appState = .capture(group: groupId)
                            }
                        }) {
                            HStack {
                                Image(systemName: "camera.viewfinder")
                                Text("Scan Receipt")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        Button(action: {
                            HapticsManager.shared.playImpact(style: .medium)
                            showingManualEntry = true
                        }) {
                            Text("Enter Manually")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(Color.black.opacity(0.6))
                        }
                        .padding(.top, 10)
                    }
                    .padding(40)
                }
                .refreshable {
                    if let g = self.group, g.isCollaborative {
                        do {
                            remoteReceipts = try await CleaveAPI.shared.fetchReceipts(groupID: g.id)
                        } catch {
                            ErrorManager.shared.showError(error.localizedDescription)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCollabSearch) {
            CollaborativeSearchSheetView(
                selectedMembers: $selectedMemberSearchResults,
                isEmbedded: false,
                onInvite: { profile in
                    Task {
                        do {
                            let updated = try await CleaveAPI.shared.addMember(
                                groupID: groupId,
                                profileID: profile.id
                            )
                            await MainActor.run {
                                store.replace(with: updated)
                            }
                        } catch {
                            ErrorManager.shared.showError(error.localizedDescription)
                        }
                    }
                },
                isAlreadyInvited: { profile in
                    store.getGroup(id: groupId)?.members.contains(where: { $0.id == profile.id }) ?? false
                }
            )
            .background(DesignSystem.canvasBeige.edgesIgnoringSafeArea(.all))
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualEntrySheetView(isPresented: $showingManualEntry, appState: $appState, groupId: groupId)
        }
        .task {
            if let g = self.group, g.isCollaborative {
                isLoadingReceipts = true
                do {
                    remoteReceipts = try await CleaveAPI.shared.fetchReceipts(groupID: g.id)
                } catch {
                    ErrorManager.shared.showError(error.localizedDescription)
                }
                isLoadingReceipts = false
            } else if let g = self.group {
                remoteReceipts = store.receipts(for: g.id)
            }
        }
    }

    private func remoteReceiptCard(receipt: RemoteReceipt) -> some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        // Compute if user is admin
        let isAdmin = supabase.currentUser?.id == receipt.adminId

        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(receipt.title)
                        .font(.headline)
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Text(displayDate(receipt.createdAt, formatter: formatter))
                            .font(.subheadline)
                            .foregroundColor(Color.white.opacity(0.7))

                        if isAdmin {
                            Text("•")
                                .font(.subheadline)
                                .foregroundColor(Color.white.opacity(0.5))
                            Text("Admin")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.15))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                }
                Spacer()
                Text(CurrencyManager.shared.format(receipt.total))
                    .font(.system(.title3, design: .rounded))
                    .foregroundColor(.white)
            }

            if let memories = receipt.memories, !memories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(memories) { memory in
                            PrivateMemoryThumbnail(
                                receiptID: receipt.id,
                                memoryID: memory.id
                            )
                        }
                    }
                }
                .accessibilityLabel("Receipt memories")
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func receiptDraftCard(_ draft: ReceiptDraft) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "icloud.slash.fill")
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(Color.black.opacity(0.25))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Receipt saved on this device")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Scanning or sync didn't finish.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
            }
            Spacer()
            Button {
                Task { await retry(draft) }
            } label: {
                if retryingDraftIDs.contains(draft.id) {
                    ProgressView().tint(.white)
                } else {
                    Text("Retry")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
            .disabled(retryingDraftIDs.contains(draft.id))
        }
        .padding(16)
        .background(Color.white.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @MainActor
    private func retry(_ draft: ReceiptDraft) async {
        guard let image = store.image(for: draft),
              let group = store.getGroup(id: groupId),
              !retryingDraftIDs.contains(draft.id) else { return }
        retryingDraftIDs.insert(draft.id)
        defer { retryingDraftIDs.remove(draft.id) }

        do {
            let receipt: RemoteReceipt
            if group.isCollaborative {
                receipt = try await CleaveAPI.shared.uploadReceiptImage(image: image, groupID: groupId)
                remoteReceipts.insert(receipt, at: 0)
            } else {
                guard let userID = SupabaseManager.shared.currentUser?.id else {
                    throw CleaveAPI.APIError.unauthorized
                }
                let parsed = try await CleaveAPI.shared.parseReceiptImage(image: image)
                receipt = RemoteReceipt(
                    id: UUID(),
                    groupId: groupId,
                    title: parsed.vendorName,
                    adminId: userID,
                    taxAmount: parsed.tax,
                    tipAmount: parsed.tip,
                    discountAmount: parsed.discount,
                    imageUrl: nil,
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    items: parsed.lineItems.map {
                        ReceiptItem(id: UUID().uuidString, name: $0.description, price: $0.price)
                    }
                )
                store.saveLocalReceipt(receipt)
                remoteReceipts = store.receipts(for: groupId)
            }
            store.removeDraft(id: draft.id)
            HapticsManager.shared.playNotification(type: .success)
        } catch {
            store.markDraftFailed(id: draft.id, message: error.localizedDescription)
            ErrorManager.shared.showError("Still saved on this device. We'll keep it here until Retry succeeds.")
        }
    }

    private func displayDate(_ value: String?, formatter: DateFormatter) -> String {
        guard let value else { return "Today" }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoFormatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
        return formatter.string(from: date ?? Date())
    }

}

private struct PrivateMemoryThumbnail: View {
    let receiptID: UUID
    let memoryID: UUID

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if didFail {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                    .background(Color.red.opacity(0.3))
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: 60, height: 60)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .clipped()
        .accessibilityLabel("Receipt memory photo")
        .task(id: memoryID) {
            do {
                let data = try await CleaveAPI.shared.fetchMemoryPhoto(
                    receiptID: receiptID,
                    memoryID: memoryID
                )
                guard let loadedImage = UIImage(data: data) else {
                    didFail = true
                    return
                }
                image = loadedImage
            } catch {
                didFail = true
            }
        }
    }
}
