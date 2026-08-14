import SwiftUI
import PhotosUI
import UIKit

struct BreakdownItem: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
}

struct SettlementHandoffSheet: View {
    let request: SettlementRequest
    let region: AppRegion

    @Environment(\.dismiss) private var dismiss
    @State private var didCopyDetails = false

    private var isCrossCurrency: Bool { request.currency != region.currency }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Text(region.flag)
                        .font(.system(size: 42))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(region.settlementMethod.displayName)
                            .font(DesignSystem.displayFont(24))
                        Text(region.currency.rawValue)
                            .font(DesignSystem.labelFont(12))
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Pay \(request.recipientName)")
                        .font(DesignSystem.titleFont(15))
                        .foregroundColor(.secondary)
                    Text(CurrencyManager.format(request.amount, currency: request.currency))
                        .font(DesignSystem.displayFont(38))
                }

                Text(instructions)
                    .font(DesignSystem.bodyFont(16))
                    .foregroundColor(.black.opacity(0.68))
                    .lineSpacing(4)

                if didCopyDetails {
                    Label("Payment details copied", systemImage: "checkmark.circle.fill")
                        .font(DesignSystem.titleFont(14))
                        .foregroundColor(.green)
                }

                Spacer()

                Button(action: launchPaymentApp) {
                    if isCrossCurrency {
                        Label("Copy original amount", systemImage: "doc.on.doc.fill")
                            .font(DesignSystem.titleFont(16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(DesignSystem.accentNavy, in: Capsule())
                    } else {
                        PaymentBrandButtonLabel(method: region.settlementMethod)
                    }
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(primaryButtonLabel)

                Button(action: copyDetails) {
                    Label("Copy payment details only", systemImage: "doc.on.doc")
                        .font(DesignSystem.titleFont(15))
                        .foregroundColor(DesignSystem.accentNavy)
                        .frame(maxWidth: .infinity)
                }

                Text("Cleave does not process, store, or verify the payment. Always confirm the recipient and amount in the payment app.")
                    .font(DesignSystem.bodyFont(12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(28)
            .background(DesignSystem.canvasBeige.ignoresSafeArea())
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.light)
    }

    private var instructions: String {
        if isCrossCurrency {
            return "This receipt is in \(request.currency.rawValue), while \(request.recipientName)'s payment method uses \(region.currency.rawValue). Cleave will not guess an exchange rate. Copy the original amount, agree on a conversion with the recipient, and verify the final amount in the payment app."
        }
        switch region.settlementMethod {
        case .venmo:
            if request.venmoUsername == nil {
                return "\(request.recipientName) has not added a Venmo username yet. Cleave can still open Venmo, but you will need to choose the recipient."
            }
            return "Cleave opens Venmo with \(request.recipientName), the amount, and note pre-filled. Verify everything in Venmo before paying."
        case .googlePayUPI:
            if request.upiID == nil {
                return "\(request.recipientName) has not added a UPI ID yet. Ask them to add it in Cleave Profile before paying."
            }
            return "Cleave opens Google Pay with \(request.recipientName)'s UPI ID, amount, and note pre-filled. Verify everything before paying."
        case .aani:
            if request.aaniID == nil {
                return "\(request.recipientName) has not added an Aani ID. Cleave copies the amount and opens Aani; verify the recipient before paying."
            }
            return "Cleave copies \(request.recipientName)'s Aani ID and amount, then opens Aani. Verify everything before paying."
        }
    }

    private var primaryButtonLabel: String {
        if isCrossCurrency { return "Copy original receipt amount" }
        switch region.settlementMethod {
        case .venmo: return "Open Venmo"
        case .googlePayUPI: return "Open Google Pay"
        case .aani: return "Copy & Open Aani"
        }
    }

    private func copyDetails() {
        if isCrossCurrency {
            UIPasteboard.general.string = "\(request.recipientName) — \(CurrencyManager.format(request.amount, currency: request.currency)) — \(request.note). Convert only after agreeing with the recipient."
        } else {
            UIPasteboard.general.string = PaymentDeepLinkBuilder.clipboardSummary(
                region: region,
                amount: request.amount,
                memberName: request.recipientName,
                note: request.note,
                paymentAddress: request.paymentAddress(for: region)
            )
        }
        didCopyDetails = true
        HapticsManager.shared.playImpact(style: .light)
    }

    private func launchPaymentApp() {
        if isCrossCurrency {
            copyDetails()
            return
        }
        switch region.settlementMethod {
        case .venmo:
            guard let url = PaymentDeepLinkBuilder.buildVenmoURL(
                recipient: request.venmoUsername,
                amount: request.amount,
                note: request.note
            ) else { return }
            open(url, fallback: PaymentDeepLinkBuilder.venmoAppStoreURL)

        case .googlePayUPI:
            copyDetails()
            guard let upiID = request.upiID,
                  let url = PaymentDeepLinkBuilder.buildGooglePayURL(
                    upiID: upiID,
                    recipientName: request.recipientName,
                    amount: request.amount,
                    note: request.note
                  ) else {
                UIApplication.shared.open(PaymentDeepLinkBuilder.googlePayAppStoreURL)
                return
            }
            open(url, fallback: PaymentDeepLinkBuilder.googlePayAppStoreURL)

        case .aani:
            copyDetails()
            UIApplication.shared.open(PaymentDeepLinkBuilder.aaniAppStoreURL)
        }
    }

    private func open(_ primaryURL: URL, fallback fallbackURL: URL) {
        UIApplication.shared.open(primaryURL, options: [:]) { success in
            guard !success else { return }
            DispatchQueue.main.async {
                UIApplication.shared.open(fallbackURL)
            }
        }
    }
}

struct SettlementRequest: Identifiable {
    let id = UUID()
    let recipientName: String
    let venmoUsername: String?
    let upiID: String?
    let aaniID: String?
    let amount: Double
    let currency: Currency
    let note: String

    func paymentAddress(for region: AppRegion) -> String? {
        switch region {
        case .unitedStates: return venmoUsername.map { "@\($0)" }
        case .india: return upiID
        case .unitedArabEmirates: return aaniID
        }
    }
}

struct BespokeBalancesView: View {
    let receiptId: String
    let groupId: UUID
    let title: String

    let items: [ReceiptItem]
    let assignments: [String: Set<String>]
    let tax: Double
    let tip: Double
    let discount: Double
    let currency: Currency
    let viewerIsAdmin: Bool
    let initialReview: ReceiptReview?
    @Binding var appState: AppState
    var namespace: Namespace.ID

    @EnvironmentObject var store: AppStore
    @AppStorage("selectedRegion") private var selectedRegion: String = ""
    @State private var memberBalances: [(String, Double, [BreakdownItem])] = []
    @State private var pendingSettlement: SettlementRequest?
    @State private var settlementRecipient: GroupMemberModel?
    @State private var pendingMemberIDs: [UUID] = []

    // Memories
    @State private var rating: Int = 0
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedPhotos: [Data] = []
    @State private var isSaving = false

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CleaveIconButton(systemName: "chevron.left", accessibilityText: "Back to receipt") {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .assignment(receiptId: receiptId, group: groupId, title: title, items: items, assignments: assignments, tax: tax, tip: tip, discount: discount, currency: currency, viewerIsAdmin: viewerIsAdmin, adminOverrideMode: false)
                        }
                    }
                    Spacer()
                    CleaveIconButton(systemName: "square.and.arrow.up", accessibilityText: "Share balances") {
                        shareSummary()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 58)

                CleaveSectionHeading("Receipt summary", eyebrow: "Your picks are saved", detail: pendingMemberIDs.isEmpty ? "Everyone has finished choosing." : "Totals update live as the group finishes choosing.")
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Finances Receipt Card
                        VStack(spacing: 0) {
                            masterSummaryCard()

                            if !pendingMemberIDs.isEmpty {
                                pendingMembersCard
                            }

                            Text("Individual Breakdown")
                                .font(DesignSystem.titleFont(17))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 30)
                                .padding(.top, 20)
                                .padding(.bottom, 10)

                            ForEach(memberBalances, id: \.0) { member, total, breakdown in
                                balanceCard(member: member, total: total, breakdown: breakdown)
                            }
                        }
                        .padding(.vertical, 30)
                        .background(DesignSystem.color(forGroupId: groupId.uuidString, in: store.groups))
                        .clipShape(ReceiptCardShape())
                        .padding(.horizontal, 20)
                        .shadow(color: DesignSystem.color(forGroupId: groupId.uuidString, in: store.groups).opacity(0.3), radius: 25, y: 15)

                        // Memories Section
                        VStack(spacing: 20) {
                            VStack(spacing: 5) {
                                Text("SAVE THE MEMORY")
                                    .font(DesignSystem.labelFont(10))
                                    .tracking(1.5)
                                    .foregroundStyle(DesignSystem.accentOrange)
                                Text("How was \(title)?")
                                    .font(DesignSystem.titleFont(19))
                                    .foregroundColor(DesignSystem.ink)
                            }

                            // Star Rating
                            HStack(spacing: 15) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.system(size: 30))
                                        .foregroundColor(star <= rating ? DesignSystem.accentOrange : DesignSystem.ink.opacity(0.16))
                                        .onTapGesture {
                                            withAnimation { rating = star }
                                        }
                                }
                            }

                            Text("Add a photo from the moment")
                                .font(DesignSystem.bodyFont(13))
                                .foregroundColor(DesignSystem.inkMuted)
                                .padding(.top, 10)

                            // Photos
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 5, matching: .images) {
                                        VStack {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 24))
                                            Text("Add Photos")
                                                .font(DesignSystem.titleFont(12))
                                        }
                                        .foregroundColor(DesignSystem.ink)
                                        .frame(width: 100, height: 100)
                                        .background(DesignSystem.fieldSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    }
                                    .onChange(of: selectedPhotoItems) { _, items in
                                        Task {
                                            selectedPhotos = []
                                            for item in items {
                                                if let data = try? await item.loadTransferable(type: Data.self) {
                                                    selectedPhotos.append(data)
                                                }
                                            }
                                        }
                                    }

                                    ForEach(selectedPhotos.indices, id: \.self) { index in
                                        if let image = UIImage(data: selectedPhotos[index]) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                        .padding(.vertical, 24)
                        .background(DesignSystem.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(DesignSystem.hairline, lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }
                }
            }

            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    Task {
                        await saveReceiptAndUploadPhotos()
                    }
                }) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        HStack {
                            Text("Save receipt")
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .black))
                        }
                    }
                }
                .primaryButton()
                .buttonStyle(PressScaleButtonStyle())
                .disabled(isSaving)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .task {
            calculateBalances()
            if store.getGroup(id: groupId)?.isCollaborative == true {
                if let initialReview {
                    applyAuthoritativeReview(initialReview)
                    settlementRecipient = store.getGroup(id: groupId)?.members
                        .first(where: { $0.id == initialReview.receipt.adminId })
                    await loadSavedExperience()
                } else {
                    async let balances: Void = loadAuthoritativeBalances()
                    async let experience: Void = loadSavedExperience()
                    async let recipient: Void = loadSettlementRecipient()
                    _ = await (balances, experience, recipient)
                }
            }
        }
        .sheet(item: $pendingSettlement) { request in
            SettlementHandoffSheet(request: request, region: settlementRegion)
        }
    }

    private func saveReceiptAndUploadPhotos() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        if store.getGroup(id: groupId)?.isCollaborative == false {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appState = .groupDetail(group: groupId)
            }
            return
        }

        do {
            let compressedPhotos = try selectedPhotos.map { data -> Data in
                guard let image = UIImage(data: data),
                      let compressedData = image.jpegData(compressionQuality: 0.6) else {
                    throw CleaveAPI.APIError.invalidResponse
                }
                return compressedData
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                if rating > 0 {
                    group.addTask {
                        try await CleaveAPI.shared.saveExperience(
                            receiptID: receiptId,
                            rating: rating
                        )
                    }
                }
                for data in compressedPhotos {
                    group.addTask {
                        _ = try await CleaveAPI.shared.uploadMemoryPhoto(
                            data: data,
                            receiptID: receiptId
                        )
                    }
                }
                try await group.waitForAll()
            }

            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appState = .groupDetail(group: groupId)
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }

    @MainActor
    private func loadSavedExperience() async {
        do {
            rating = try await CleaveAPI.shared.fetchExperienceRating(receiptID: receiptId) ?? 0
        } catch {
            // Rating is supplementary; balances and receipt review remain usable.
            rating = 0
        }
    }

    private func masterSummaryCard() -> some View {
        let subtotal = items.reduce(0) { $0 + $1.price }

        return VStack(spacing: 12) {
            HStack {
                Text("Receipt Subtotal")
                    .font(DesignSystem.bodyFont(14))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(CurrencyManager.shared.format(subtotal, currency: currency))
                    .font(DesignSystem.bodyFont(14))
                    .foregroundColor(.white.opacity(0.8))
            }

            if tax > 0 {
                HStack {
                    Text("Tax")
                        .font(DesignSystem.bodyFont(14))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(CurrencyManager.shared.format(tax, currency: currency))
                        .font(DesignSystem.bodyFont(14))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            if tip > 0 {
                HStack {
                    Text("Tip")
                        .font(DesignSystem.bodyFont(14))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(CurrencyManager.shared.format(tip, currency: currency))
                        .font(DesignSystem.bodyFont(14))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            Divider().background(Color.white.opacity(0.3)).padding(.vertical, 4)

            HStack {
                Text("Receipt Total")
                    .font(DesignSystem.titleFont(18))
                    .foregroundColor(.white)
                Spacer()
                Text(CurrencyManager.shared.format(fullReceiptTotal, currency: currency))
                    .font(DesignSystem.displayFont(19))
                    .foregroundColor(.white)
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var fullReceiptTotal: Double {
        let subtotal = items.reduce(0) { $0 + $1.price }
        return subtotal + tax + tip - discount
    }

    private func balanceCard(member: String, total: Double, breakdown: [BreakdownItem]) -> some View {
        let displayName = store.getGroup(id: groupId)?.members
            .first(where: { $0.id.uuidString == member })?.preferredName ?? "Member"
        return VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(displayName.prefix(1)))
                            .font(DesignSystem.titleFont(18))
                            .foregroundColor(.white)
                    )

                Text(displayName)
                    .font(DesignSystem.titleFont(18))
                    .foregroundColor(.white)
                    .padding(.leading, 10)

                Spacer()

                Text(CurrencyManager.shared.format(total, currency: currency))
                    .font(DesignSystem.displayFont(22))
                    .foregroundColor(.white)
            }
            .padding(24)

            // Settlement button
            if total > 0 && member == DemoMode.effectiveUserID?.uuidString && !viewerIsAdmin {
                let isGroupCollaborative = store.getGroup(id: groupId)?.isCollaborative ?? false
                let unassignedExists = items.contains { (assignments[$0.id] ?? []).isEmpty }
                let isLocked = isGroupCollaborative && unassignedExists

                Button(action: {
                    if isLocked { return }
                    pendingSettlement = SettlementRequest(
                        recipientName: settlementRecipient?.preferredName ?? "the receipt payer",
                        venmoUsername: settlementRecipient?.venmoUsername,
                        upiID: settlementRecipient?.upiId,
                        aaniID: settlementRecipient?.aaniId,
                        amount: total,
                        currency: currency,
                        note: "Cleave - \(title)"
                    )
                }) {
                    Group {
                        if isLocked {
                            HStack {
                            Image(systemName: "lock.fill")
                            Text("Waiting for everyone...")
                            }
                            .font(DesignSystem.titleFont(13))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.gray.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        } else {
                            PaymentBrandButtonLabel(method: settlementRegion.settlementMethod, compact: true)
                        }
                    }
                }
                .disabled(isLocked)
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(isLocked ? "Waiting for everyone" : activeRegion.settlementMethod.actionLabel)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            if !breakdown.isEmpty {
                Divider().background(Color.white.opacity(0.3)).padding(.horizontal, 24)

                VStack(spacing: 8) {
                    ForEach(breakdown, id: \.id) { item in
                        HStack {
                            Text(item.name)
                                .font(DesignSystem.bodyFont(13))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Text(CurrencyManager.shared.format(item.amount, currency: currency))
                                .font(DesignSystem.bodyFont(13))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .shadow(color: Color.black.opacity(0.15), radius: 15, y: 8)
    }

    private var activeRegion: AppRegion {
        AppRegion(rawValue: selectedRegion) ?? RegionManager.shared.currentRegion
    }

    private var settlementRegion: AppRegion {
        settlementRecipient?.regionCode.flatMap(AppRegion.init(rawValue:)) ?? activeRegion
    }

    private func calculateBalances() {
        var balances: [String: Double] = [:]
        var breakdowns: [String: [BreakdownItem]] = [:]
        var subtotal = 0.0

        // 1. Calculate item splits
        for item in items {
            let assignedMembers = assignments[item.id] ?? []
            if !assignedMembers.isEmpty {
                let splitAmount = item.price / Double(assignedMembers.count)
                for member in assignedMembers {
                    balances[member, default: 0.0] += splitAmount
                    breakdowns[member, default: []].append(BreakdownItem(name: item.name, amount: splitAmount))
                }
                subtotal += item.price
            }
        }

        // 2. Proportionally distribute tax, tip, and discount
        let itemOnlyBalances = balances
        if subtotal > 0 {
            for (member, amount) in itemOnlyBalances {
                let proportion = amount / subtotal

                if tax > 0 {
                    let taxShare = proportion * tax
                    balances[member]! += taxShare
                    breakdowns[member, default: []].append(BreakdownItem(name: "Tax Share", amount: taxShare))
                }
                if tip > 0 {
                    let tipShare = proportion * tip
                    balances[member]! += tipShare
                    breakdowns[member, default: []].append(BreakdownItem(name: "Tip Share", amount: tipShare))
                }
                if discount > 0 {
                    let discountShare = proportion * discount
                    balances[member]! -= discountShare
                    breakdowns[member, default: []].append(BreakdownItem(name: "Discount Share", amount: -discountShare))
                }
            }
        }

        memberBalances = balances.map { ($0.key, $0.value, breakdowns[$0.key] ?? []) }.sorted { $0.1 > $1.1 }
    }

    private func loadAuthoritativeBalances() async {
        do {
            let review = try await CleaveAPI.shared.fetchReceiptReview(receiptID: receiptId)
            applyAuthoritativeReview(review)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }

    @MainActor
    private func applyAuthoritativeReview(_ review: ReceiptReview) {
        pendingMemberIDs = (review.receipt.participants ?? [])
            .filter { !$0.hasSubmitted }
            .map(\.userId)
        memberBalances = review.balances.map { balance in
            let memberID = balance.userId.uuidString
            var breakdown = balance.items.map {
                BreakdownItem(name: $0.name, amount: $0.amount)
            }
            if balance.taxShare > 0 { breakdown.append(BreakdownItem(name: "Tax share", amount: balance.taxShare)) }
            if balance.tipShare > 0 { breakdown.append(BreakdownItem(name: "Tip share", amount: balance.tipShare)) }
            if balance.discountShare > 0 { breakdown.append(BreakdownItem(name: "Discount share", amount: -balance.discountShare)) }
            return (memberID, balance.totalOwed, breakdown)
        }.sorted { $0.1 > $1.1 }
    }

    private var pendingMembersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Waiting on", systemImage: "clock")
                .font(DesignSystem.titleFont(14))
            ForEach(pendingMemberIDs, id: \.self) { memberID in
                let name = store.getGroup(id: groupId)?.members.first(where: { $0.id == memberID })?.preferredName ?? "Member"
                HStack {
                    Text(name)
                    Spacer()
                    Text("PENDING")
                        .font(DesignSystem.labelFont(9))
                        .tracking(1)
                }
                .font(DesignSystem.bodyFont(13))
            }
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(18)
        .background(Color.black.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    @MainActor
    private func loadSettlementRecipient() async {
        do {
            let receiptUUID = UUID(uuidString: receiptId)
            let receipt = try await CleaveAPI.shared.fetchReceipts(groupID: groupId)
                .first(where: { $0.id == receiptUUID })
            guard let adminID = receipt?.adminId else { return }
            settlementRecipient = store.getGroup(id: groupId)?.members.first(where: { $0.id == adminID })
        } catch {
            settlementRecipient = nil
        }
    }

    private func shareSummary() {
        var summary = "Cleave Split: \(title)\n\n"

        let subtotal = items.reduce(0) { $0 + $1.price }

        summary += "Subtotal: \(CurrencyManager.shared.format(subtotal, currency: currency))\n"
        summary += "Tax: \(CurrencyManager.shared.format(tax, currency: currency))\n"
        summary += "Tip: \(CurrencyManager.shared.format(tip, currency: currency))\n"
        if discount > 0 {
            summary += "Discount: -\(CurrencyManager.shared.format(discount, currency: currency))\n"
        }
        summary += "Total: \(CurrencyManager.shared.format(fullReceiptTotal, currency: currency))\n\n"

        summary += "--- Balances ---\n"
        for (member, amount, _) in memberBalances {
            if amount > 0 {
                let name = store.getGroup(id: groupId)?.members
                    .first(where: { $0.id.uuidString == member })?.preferredName ?? "Member"
                summary += "\(name) owes \(CurrencyManager.shared.format(amount, currency: currency))\n"
            }
        }

        let activityVC = UIActivityViewController(activityItems: [summary], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {

            // For iPad support
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            rootVC.present(activityVC, animated: true)
        }
    }
}
