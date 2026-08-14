import SwiftUI

struct BespokeGroupDetailView: View {
    let groupId: UUID
    let color: Color
    @Binding var appState: AppState
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var remoteReceipts: [RemoteReceipt] = []
    @State private var isLoadingReceipts: Bool = false
    @State private var showingCollabSearch: Bool = false
    @State private var showingManualEntry: Bool = false
    @State private var selectedMemberSearchResults: [Profile] = []
    @State private var retryingDraftIDs: Set<UUID> = []
    @State private var selectedMomentsReceipt: RemoteReceipt?
    @State private var receiptPendingDeletion: RemoteReceipt?
    @State private var isDeletingReceipt = false

    @ObservedObject private var supabase = SupabaseManager.shared

    var group: GroupModel? {
        store.getGroup(id: groupId)
    }

    var body: some View {
        ZStack(alignment: .top) {
            color
                .ignoresSafeArea()

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
                    .padding(.top, 60)

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
                                            Text(String(member.preferredName.prefix(1)))
                                                .font(DesignSystem.titleFont(20))
                                                .foregroundColor(.white)
                                        )
                                    Text(member.preferredName)
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
                                message: "Scan your first receipt to start splitting.",
                                onDarkBackground: true
                            )
                            .padding(.top, 40)
                        } else {
                            VStack(spacing: 16) {
                                ForEach(remoteReceipts) { receipt in
                                    remoteReceiptCard(receipt: receipt)
                                }
                            }
                        }

                    }
                    .padding(40)
                    .padding(.bottom, 94)
                    }
                }
                .refreshable {
                    await refreshReceipts(showError: true)
                }
                .overlay(alignment: .bottom) {
                    receiptCreationBar
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
        .sheet(item: $selectedMomentsReceipt) { receipt in
            ReceiptMomentsSheet(receipt: receipt, members: group?.members ?? [])
                .presentationCornerRadius(32)
        }
        .alert("Delete this receipt?", isPresented: Binding(
            get: { receiptPendingDeletion != nil },
            set: { if !$0 { receiptPendingDeletion = nil } }
        )) {
            Button("Delete receipt", role: .destructive) {
                guard let receipt = receiptPendingDeletion else { return }
                Task { await deleteReceipt(receipt) }
            }
            Button("Keep receipt", role: .cancel) { receiptPendingDeletion = nil }
        } message: {
            Text("This permanently removes the receipt, everyone’s item claims, payment status, ratings, and memory photos.")
        }
        .task(id: groupId) {
            if let g = self.group, g.isCollaborative {
                await refreshReceipts(showLoading: true, showError: true)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    await refreshReceipts()
                }
            } else if let g = self.group {
                remoteReceipts = store.receipts(for: g.id)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, group?.isCollaborative == true else { return }
            Task { await refreshReceipts() }
        }
    }

    private var receiptCreationBar: some View {
        HStack(spacing: 10) {
            Button {
                HapticsManager.shared.playImpact(style: .medium)
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    appState = .capture(group: groupId)
                }
            } label: {
                Label("Scan receipt", systemImage: "camera.viewfinder")
                    .font(DesignSystem.titleFont(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black.opacity(0.9), in: Capsule())
            }
            .buttonStyle(PressScaleButtonStyle())

            Button {
                HapticsManager.shared.playImpact(style: .medium)
                showingManualEntry = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.9), in: Circle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel("Enter receipt manually")
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.38), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.22), radius: 16, y: 8)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func remoteReceiptCard(receipt: RemoteReceipt) -> some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let isAdmin = supabase.currentUser?.id == receipt.adminId
        let adminName = group?.members.first(where: { $0.id == receipt.adminId })?.preferredName ?? "Member"
        let myParticipant = receipt.participants?.first(where: { $0.userId == supabase.currentUser?.id })
        let needsMyClaim = myParticipant?.hasSubmitted == false
        let submittedCount = receipt.participants?.filter(\.hasSubmitted).count ?? 0
        let participantCount = receipt.participants?.count ?? group?.members.count ?? 0
        let momentCount = (receipt.memories?.count ?? 0) + (receipt.experiences?.count ?? 0)

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

                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(Color.white.opacity(0.5))
                        Text("Admin: \(adminName)\(isAdmin ? " (You)" : "")")
                            .font(.caption.bold())
                            .lineLimit(1)
                            .foregroundColor(.white.opacity(0.86))
                    }
                }
                Spacer()
                Text(CurrencyManager.shared.format(receipt.total, currency: receipt.currency))
                    .font(DesignSystem.titleFont(18))
                    .foregroundColor(.white)
            }

            HStack(spacing: 8) {
                Image(systemName: needsMyClaim ? "hand.tap.fill" : (isAdmin ? "slider.horizontal.3" : "person.crop.circle"))
                Text(needsMyClaim ? "Choose your items" : (isAdmin ? "Review receipt" : "View your share"))
                    .font(DesignSystem.titleFont(14))
                Spacer()
                if participantCount > 0 {
                    Text("\(submittedCount)/\(participantCount) DONE")
                        .font(DesignSystem.labelFont(8))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(.white.opacity(0.9))
            .contentShape(Rectangle())
            .onTapGesture {
                openReceipt(receipt, isAdmin: isAdmin, needsMyClaim: needsMyClaim)
            }

            if momentCount > 0 {
                Button {
                    selectedMomentsReceipt = receipt
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Moments")
                        Text("\(momentCount)")
                            .foregroundStyle(.white.opacity(0.62))
                        Spacer()
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    .font(DesignSystem.titleFont(13))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .background(Color.black.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            if isAdmin && group?.isCollaborative == true {
                Button(role: .destructive) {
                    receiptPendingDeletion = receipt
                } label: {
                    Label("Delete receipt", systemImage: "trash")
                }
            }
        }
    }

    private func openReceipt(_ receipt: RemoteReceipt, isAdmin: Bool, needsMyClaim: Bool) {
        HapticsManager.shared.playImpact(style: .light)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            if group?.isCollaborative == true && needsMyClaim {
                appState = .assignment(
                    receiptId: receipt.id.uuidString,
                    group: groupId,
                    title: receipt.title,
                    items: receipt.items,
                    assignments: receipt.assignmentMap,
                    tax: receipt.taxAmount,
                    tip: receipt.tipAmount,
                    discount: receipt.discountAmount,
                    currency: receipt.currency,
                    viewerIsAdmin: isAdmin,
                    adminOverrideMode: false
                )
            } else if group?.isCollaborative == true {
                appState = .receiptReview(receipt: receipt, group: groupId)
            } else {
                appState = .assignment(
                    receiptId: receipt.id.uuidString,
                    group: groupId,
                    title: receipt.title,
                    items: receipt.items,
                    assignments: receipt.assignmentMap,
                    tax: receipt.taxAmount,
                    tip: receipt.tipAmount,
                    discount: receipt.discountAmount,
                    currency: receipt.currency,
                    viewerIsAdmin: true,
                    adminOverrideMode: false
                )
            }
        }
    }

    @MainActor
    private func refreshReceipts(showLoading: Bool = false, showError: Bool = false) async {
        guard let group, group.isCollaborative else { return }
        if showLoading && remoteReceipts.isEmpty { isLoadingReceipts = true }
        defer { isLoadingReceipts = false }
        do {
            let refreshed = try await CleaveAPI.shared.fetchReceipts(groupID: group.id)
            if refreshed != remoteReceipts {
                remoteReceipts = refreshed
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            if showError { ErrorManager.shared.showError(error.localizedDescription) }
        }
    }

    @MainActor
    private func deleteReceipt(_ receipt: RemoteReceipt) async {
        guard !isDeletingReceipt else { return }
        isDeletingReceipt = true
        defer { isDeletingReceipt = false }
        do {
            try await CleaveAPI.shared.deleteReceipt(receiptID: receipt.id)
            remoteReceipts.removeAll { $0.id == receipt.id }
            receiptPendingDeletion = nil
            HapticsManager.shared.playNotification(type: .success)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
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
                    .font(DesignSystem.titleFont(15))
                    .foregroundColor(.white)
                Text(draft.errorMessage ?? "Scanning or sync didn't finish.")
                    .font(DesignSystem.bodyFont(13))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(3)
            }
            Spacer()
            Button {
                Task { await retry(draft) }
            } label: {
                if retryingDraftIDs.contains(draft.id) {
                    ProgressView().tint(.white)
                } else {
                    Text("Retry")
                        .font(DesignSystem.titleFont(14))
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
        .contextMenu {
            Button(role: .destructive) {
                store.removeDraft(id: draft.id)
            } label: {
                Label("Discard local draft", systemImage: "trash")
            }
        }
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
                    requestID: draft.id
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
                    currencyCode: parsed.currencyCode ?? RegionManager.shared.currentRegion.currency,
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
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            let recovery = ReceiptScanRecovery.message(for: error)
            store.markDraftFailed(id: draft.id, message: recovery)
            ErrorManager.shared.showError("Still saved on this device. \(recovery)")
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
    var size: CGFloat = 60

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
        .frame(width: size, height: size)
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

private struct ReceiptMomentsSheet: View {
    let receipt: RemoteReceipt
    let members: [GroupMemberModel]
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MOMENTS")
                            .font(DesignSystem.labelFont(10))
                            .tracking(1.6)
                            .foregroundStyle(DesignSystem.accentOrange)
                        Text(receipt.title)
                            .font(DesignSystem.displayFont(28))
                            .foregroundStyle(DesignSystem.ink)
                        Text("Everyone’s rating and photos, together.")
                            .font(DesignSystem.bodyFont(14))
                            .foregroundStyle(DesignSystem.inkMuted)
                    }

                    if let experiences = receipt.experiences, !experiences.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            momentsSectionTitle("RATINGS", count: experiences.count)
                            VStack(spacing: 10) {
                                ForEach(experiences.sorted { $0.userId.uuidString < $1.userId.uuidString }, id: \.userId) { experience in
                                    HStack(spacing: 12) {
                                        Text(String(memberName(experience.userId).prefix(1)).uppercased())
                                            .font(DesignSystem.titleFont(14))
                                            .foregroundStyle(.white)
                                            .frame(width: 38, height: 38)
                                            .background(DesignSystem.accentNavy)
                                            .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(memberName(experience.userId))
                                                .font(DesignSystem.titleFont(15))
                                                .foregroundStyle(DesignSystem.ink)
                                            Text("\(experience.rating) out of 5")
                                                .font(DesignSystem.bodyFont(11))
                                                .foregroundStyle(DesignSystem.inkMuted)
                                        }
                                        Spacer()
                                        HStack(spacing: 2) {
                                            ForEach(1...5, id: \.self) { star in
                                                Image(systemName: star <= experience.rating ? "star.fill" : "star")
                                                    .font(.system(size: 12, weight: .bold))
                                            }
                                        }
                                        .foregroundStyle(DesignSystem.accentOrange)
                                    }
                                    .padding(14)
                                    .background(DesignSystem.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(DesignSystem.hairline, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }

                    if let memories = receipt.memories, !memories.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            momentsSectionTitle("PHOTOS", count: memories.count)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(memories) { memory in
                                    VStack(alignment: .leading, spacing: 6) {
                                        PrivateMemoryThumbnail(receiptID: receipt.id, memoryID: memory.id, size: 108)
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        Text(memberName(memory.userId))
                                            .font(DesignSystem.bodyFont(11))
                                            .foregroundStyle(DesignSystem.inkMuted)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    } else if (receipt.experiences ?? []).isEmpty {
                        EmptyStateView(
                            iconName: "sparkles",
                            title: "No moments yet",
                            message: "Ratings and photos appear here after members add them.",
                            onDarkBackground: false
                        )
                    }
                }
                .padding(22)
            }
            .background(DesignSystem.canvasBeige.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(DesignSystem.titleFont(15))
                        .foregroundStyle(DesignSystem.ink)
                }
            }
            .toolbarBackground(DesignSystem.canvasBeige, for: .navigationBar)
        }
    }

    private func momentsSectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(DesignSystem.labelFont(10))
                .tracking(1.4)
                .foregroundStyle(DesignSystem.inkMuted)
            Text("\(count)")
                .font(DesignSystem.labelFont(9))
                .foregroundStyle(DesignSystem.ink)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(DesignSystem.fieldSurface)
                .clipShape(Capsule())
        }
    }

    private func memberName(_ id: UUID) -> String {
        members.first(where: { $0.id == id })?.preferredName ?? "Member"
    }
}
