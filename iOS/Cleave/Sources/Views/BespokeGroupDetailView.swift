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
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                appState = .home
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.16))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        Spacer()
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 8)

                    Text(group.name)
                        .font(DesignSystem.displayFont(42))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 30)

                    Text("\(group.members.count) members")
                        .font(DesignSystem.labelFont(11))
                        .tracking(1.5)
                        .textCase(.uppercase)
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
                                                .font(DesignSystem.titleFont(20))
                                                .foregroundColor(.white)
                                        )
                                    Text(member.displayName)
                                        .font(DesignSystem.bodyFont(11))
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
                                            .font(DesignSystem.bodyFont(11))
                                            .foregroundColor(Color.white.opacity(0.7))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 30)
                    }
                    .frame(height: 100)

                    // Action Area
                    VStack(spacing: 24) {
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
                            .padding(.vertical, 32)
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
                                    .font(DesignSystem.titleFont(18))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                ZStack {
                                    color
                                    Color.black.opacity(color == DesignSystem.cardNavy ? 0.12 : 0.24)
                                }
                            )
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                            .shadow(color: color.opacity(0.42), radius: 12, y: 6)
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        Button(action: {
                            HapticsManager.shared.playImpact(style: .medium)
                            showingManualEntry = true
                        }) {
                            Label("Enter manually", systemImage: "square.and.pencil")
                                .font(DesignSystem.titleFont(15))
                                .foregroundColor(.white.opacity(0.92))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .overlay(Capsule().stroke(Color.white.opacity(0.32), lineWidth: 1))
                        }
                        .buttonStyle(PressScaleButtonStyle())
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 18)
                    .padding(.bottom, 42)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
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
                .presentationCornerRadius(34)
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
                        .font(DesignSystem.titleFont(17))
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Text(displayDate(receipt.createdAt, formatter: formatter))
                            .font(DesignSystem.bodyFont(13))
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
                Text(CurrencyManager.format(receipt.total, currency: receipt.currency))
                    .font(DesignSystem.titleFont(18))
                    .foregroundColor(.white)
            }

            HStack(spacing: 8) {
                Text("Review and split")
                    .font(DesignSystem.titleFont(14))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(.white.opacity(0.9))

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
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            HapticsManager.shared.playImpact(style: .light)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                appState = .assignment(
                    receiptId: receipt.id.uuidString,
                    group: groupId,
                    title: receipt.title,
                    items: receipt.items,
                    assignments: [:],
                    tax: receipt.taxAmount,
                    tip: receipt.tipAmount,
                    discount: receipt.discountAmount,
                    currency: receipt.currency
                )
            }
        }
    }

    private func receiptDraftCard(_ draft: ReceiptDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "icloud.slash.fill")
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.black.opacity(0.25))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Receipt saved on this device")
                        .font(DesignSystem.titleFont(15))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(draft.errorMessage ?? "Scanning or sync didn't finish.")
                        .font(DesignSystem.bodyFont(13))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                Task { await retry(draft) }
            } label: {
                HStack(spacing: 8) {
                    if retryingDraftIDs.contains(draft.id) {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry scan")
                            .font(DesignSystem.titleFont(14))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 42)
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
                receipt = try await CleaveAPI.shared.uploadReceiptImage(
                    image: image,
                    groupID: groupId,
                    currency: CurrencyManager.shared.currentCurrency
                )
                remoteReceipts.insert(receipt, at: 0)
            } else {
                guard let userID = DemoMode.effectiveUserID else {
                    throw CleaveAPI.APIError.unauthorized
                }
                let parsed: ParsedReceiptResponse
                if DemoMode.isEnabled {
                    parsed = ParsedReceiptResponse(
                        vendorName: "Demo Market",
                        tax: 2.35,
                        tip: 0,
                        discount: 1,
                        total: 28.85,
                        lineItems: [
                            .init(description: "Sandwich", price: 12.50),
                            .init(description: "Iced Coffee", price: 7.00),
                            .init(description: "Fruit Bowl", price: 8.00)
                        ]
                    )
                } else {
                    parsed = try await CleaveAPI.shared.parseReceiptImage(image: image)
                }
                receipt = RemoteReceipt(
                    id: UUID(),
                    groupId: groupId,
                    title: parsed.vendorName,
                    adminId: userID,
                    currencyCode: CurrencyManager.shared.currentCurrency.rawValue,
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
            if let apiError = error as? CleaveAPI.APIError,
               !apiError.shouldKeepReceiptDraft {
                store.removeDraft(id: draft.id)
                ErrorManager.shared.showError(error.localizedDescription)
            } else {
                store.markDraftFailed(id: draft.id, message: error.localizedDescription)
                ErrorManager.shared.showError("The receipt is still saved here. Retry after your connection or session is restored.")
            }
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
