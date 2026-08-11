import SwiftUI
import PhotosUI
import UIKit

struct BreakdownItem: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
}

private struct SettlementHandoffSheet: View {
    let request: SettlementRequest

    @Environment(\.dismiss) private var dismiss
    @State private var didCopyDetails = false
    @State private var didLaunchPaymentApp = false
    @State private var isConfirming = false
    @State private var isConfirmed = false
    @State private var confirmationError: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Text(request.paymentRegion?.flag ?? "🌐")
                        .font(.system(size: 42))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(request.paymentRegion?.settlementMethod.displayName ?? "Payment details")
                            .font(DesignSystem.displayFont(24))
                        Text(request.currency.rawValue)
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

                if let paymentRegion = request.paymentRegion {
                    Button(action: launchPaymentApp) {
                        PaymentBrandButtonLabel(method: paymentRegion.settlementMethod)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .accessibilityLabel(primaryButtonLabel)
                }

                Button(action: copyDetails) {
                    Label("Copy payment details only", systemImage: "doc.on.doc")
                        .font(DesignSystem.titleFont(15))
                        .foregroundColor(DesignSystem.accentNavy)
                        .frame(maxWidth: .infinity)
                }

                if didLaunchPaymentApp && !isConfirmed {
                    Button {
                        Task { await confirmPayment() }
                    } label: {
                        if isConfirming {
                            ProgressView().tint(.white)
                        } else {
                            Label("I completed the payment", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .primaryButton()
                    .disabled(isConfirming)
                }

                if isConfirmed {
                    Label("Marked confirmed in Cleave", systemImage: "checkmark.seal.fill")
                        .font(DesignSystem.titleFont(14))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                } else if let confirmationError {
                    Text(confirmationError)
                        .font(DesignSystem.bodyFont(12))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                }

                Text("Cleave does not process or automatically verify payments. Only tap the confirmation button after the payment app reports success.")
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
        guard let paymentRegion = request.paymentRegion else {
            return "The receipt currency does not match \(request.recipientName)’s saved payment method. Copy the details and agree on a compatible payment method outside Cleave."
        }
        switch paymentRegion.settlementMethod {
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
            return "Aani does not publish a consumer iOS payment-link format. Cleave copies the amount and opens the official Aani App Store page; continue in Aani or an Aani-enabled bank app."
        }
    }

    private var primaryButtonLabel: String {
        guard let paymentRegion = request.paymentRegion else { return "Copy payment details" }
        switch paymentRegion.settlementMethod {
        case .venmo: return "Open Venmo"
        case .googlePayUPI: return "Open Google Pay"
        case .aani: return "Copy & Open Aani"
        }
    }

    private func copyDetails() {
        UIPasteboard.general.string = PaymentDeepLinkBuilder.clipboardSummary(
            currency: request.currency,
            amount: request.amount,
            memberName: request.recipientName,
            note: request.note,
            paymentAddress: request.paymentAddress
        )
        didCopyDetails = true
        HapticsManager.shared.playImpact(style: .light)
    }

    private func launchPaymentApp() {
        guard let paymentRegion = request.paymentRegion else {
            copyDetails()
            return
        }
        didLaunchPaymentApp = true
        switch paymentRegion.settlementMethod {
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

    @MainActor
    private func confirmPayment() async {
        isConfirming = true
        confirmationError = nil
        do {
            _ = try await CleaveAPI.shared.confirmSettlement(id: request.id)
            isConfirmed = true
            HapticsManager.shared.playNotification(type: .success)
        } catch {
            confirmationError = error.localizedDescription
        }
        isConfirming = false
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

private struct SettlementRequest: Identifiable {
    let id: UUID
    let recipientName: String
    let venmoUsername: String?
    let upiID: String?
    let amount: Double
    let note: String
    let currency: Currency
    let paymentRegion: AppRegion?

    var paymentAddress: String? {
        switch paymentRegion {
        case .unitedStates: return venmoUsername.map { "@\($0)" }
        case .india: return upiID
        case .unitedArabEmirates, .none: return nil
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
    @Binding var appState: AppState
    var namespace: Namespace.ID

    @EnvironmentObject var store: AppStore
    @State private var memberBalances: [(String, Double, [BreakdownItem])] = []
    @State private var pendingSettlement: SettlementRequest?
    @State private var settlementRecipient: GroupMemberModel?
    @State private var isInitiatingSettlement = false

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
                            appState = .assignment(receiptId: receiptId, group: groupId, title: title, items: items, assignments: assignments, tax: tax, tip: tip, discount: discount, currency: currency)
                        }
                    }
                    Spacer()
                    CleaveIconButton(systemName: "square.and.arrow.up", accessibilityText: "Share balances") {
                        shareSummary()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 58)

                CleaveSectionHeading("Everyone's share", eyebrow: "Balances", detail: "Clear totals, ready to settle.")
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Finances Receipt Card
                        VStack(spacing: 0) {
                            masterSummaryCard()

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
                async let balances: Void = loadAuthoritativeBalances()
                async let experience: Void = loadSavedExperience()
                async let recipient: Void = loadSettlementRecipient()
                _ = await (balances, experience, recipient)
            }
        }
        .sheet(item: $pendingSettlement) { request in
            SettlementHandoffSheet(request: request)
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
            if rating > 0 {
                try await CleaveAPI.shared.saveExperience(
                    receiptID: receiptId,
                    rating: rating
                )
            }

            for data in selectedPhotos {
                guard let image = UIImage(data: data),
                      let compressedData = image.jpegData(compressionQuality: 0.6) else {
                    throw CleaveAPI.APIError.invalidResponse
                }
                _ = try await CleaveAPI.shared.uploadMemoryPhoto(
                    data: compressedData,
                    receiptID: receiptId
                )
            }

            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appState = .groupDetail(group: groupId)
            }
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
                Text(CurrencyManager.format(subtotal, currency: currency))
                    .font(DesignSystem.bodyFont(14))
                    .foregroundColor(.white.opacity(0.8))
            }

            if tax > 0 {
                HStack {
                    Text("Tax")
                        .font(DesignSystem.bodyFont(14))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(CurrencyManager.format(tax, currency: currency))
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
                    Text(CurrencyManager.format(tip, currency: currency))
                        .font(DesignSystem.bodyFont(14))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            Divider().background(Color.white.opacity(0.3)).padding(.vertical, 4)

            HStack {
                Text("Total Allocated")
                    .font(DesignSystem.titleFont(18))
                    .foregroundColor(.white)
                Spacer()
                Text(CurrencyManager.format(fullReceiptTotal, currency: currency))
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
            .first(where: { $0.id.uuidString == member })?.displayName ?? "Member"
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

                Text(CurrencyManager.format(total, currency: currency))
                    .font(DesignSystem.displayFont(22))
                    .foregroundColor(.white)
            }
            .padding(24)

            // Settlement button
            if canSettle(member: member, total: total) {
                let isGroupCollaborative = store.getGroup(id: groupId)?.isCollaborative ?? false
                let unassignedExists = items.contains { (assignments[$0.id] ?? []).isEmpty }
                let isLocked = isGroupCollaborative && unassignedExists

                Button(action: {
                    if isLocked { return }
                    Task { await initiateSettlement() }
                }) {
                    Group {
                        if isInitiatingSettlement {
                            ProgressView().tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        } else if isLocked {
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
                            if let paymentRegion = compatiblePaymentRegion {
                                PaymentBrandButtonLabel(method: paymentRegion.settlementMethod, compact: true)
                            } else {
                                Label("Review payment options", systemImage: "arrow.up.right.square")
                                    .font(DesignSystem.titleFont(13))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(DesignSystem.accentNavy)
                                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                        }
                    }
                }
                .disabled(isLocked || isInitiatingSettlement)
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(isLocked ? "Waiting for everyone" : "Review settlement")
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
                            Text(CurrencyManager.format(item.amount, currency: currency))
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

    private var compatiblePaymentRegion: AppRegion? {
        guard let rawRegion = settlementRecipient?.regionCode,
              let region = AppRegion(rawValue: rawRegion),
              region.currency == currency else { return nil }
        return region
    }

    private func canSettle(member: String, total: Double) -> Bool {
        guard total > 0,
              store.getGroup(id: groupId)?.isCollaborative == true,
              let currentUserID = SupabaseManager.shared.currentUser?.id,
              member == currentUserID.uuidString,
              settlementRecipient?.id != currentUserID else { return false }
        return true
    }

    @MainActor
    private func initiateSettlement() async {
        guard !isInitiatingSettlement, let recipient = settlementRecipient else { return }
        isInitiatingSettlement = true
        defer { isInitiatingSettlement = false }
        do {
            let settlement = try await CleaveAPI.shared.initiateSettlement(
                receiptID: receiptId,
                recipientID: recipient.id
            )
            guard let settlementCurrency = Currency(rawValue: settlement.currencyCode) else {
                throw CleaveAPI.APIError.decoding
            }
            pendingSettlement = SettlementRequest(
                id: settlement.id,
                recipientName: recipient.displayName,
                venmoUsername: recipient.venmoUsername,
                upiID: recipient.upiId,
                amount: settlement.amount,
                note: "Cleave - \(title)",
                currency: settlementCurrency,
                paymentRegion: compatiblePaymentRegion
            )
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }

    private func calculateBalances() {
        var balanceUnits: [String: Int64] = [:]
        var breakdowns: [String: [BreakdownItem]] = [:]
        var assignedSubtotalUnits: Int64 = 0

        // Split every item in deterministic minor units so no cent is lost.
        for item in items {
            let assignedMembers = (assignments[item.id] ?? []).sorted()
            guard !assignedMembers.isEmpty else { continue }
            let itemUnits = Money(amount: item.price, currency: currency).minorUnits
            let base = itemUnits / Int64(assignedMembers.count)
            let remainder = Int(itemUnits % Int64(assignedMembers.count))
            for (index, member) in assignedMembers.enumerated() {
                let shareUnits = base + (index < remainder ? 1 : 0)
                balanceUnits[member, default: 0] += shareUnits
                breakdowns[member, default: []].append(
                    BreakdownItem(
                        name: item.name,
                        amount: Money(minorUnits: shareUnits, currency: currency).amount
                    )
                )
            }
            assignedSubtotalUnits += itemUnits
        }

        guard assignedSubtotalUnits > 0 else {
            memberBalances = []
            return
        }

        let itemWeights = balanceUnits
        let components: [(String, Int64, Bool)] = [
            ("Tax Share", Money(amount: tax, currency: currency).minorUnits, false),
            ("Tip Share", Money(amount: tip, currency: currency).minorUnits, false),
            ("Discount Share", Money(amount: discount, currency: currency).minorUnits, true),
        ]
        for (label, totalUnits, subtract) in components where totalUnits > 0 {
            let allocations = MoneyAllocator.allocate(
                totalMinorUnits: totalUnits,
                weights: itemWeights
            )
            for member in itemWeights.keys.sorted() {
                let units = allocations[member, default: 0]
                balanceUnits[member, default: 0] += subtract ? -units : units
                breakdowns[member, default: []].append(
                    BreakdownItem(
                        name: label,
                        amount: Money(
                            minorUnits: subtract ? -units : units,
                            currency: currency
                        ).amount
                    )
                )
            }
        }

        memberBalances = balanceUnits.map {
            ($0.key, Money(minorUnits: $0.value, currency: currency).amount, breakdowns[$0.key] ?? [])
        }.sorted { $0.1 > $1.1 }
    }

    private func loadAuthoritativeBalances() async {
        do {
            let remoteBalances = try await CleaveAPI.shared.fetchBalances(receiptID: receiptId)
            let breakdowns = Dictionary(
                uniqueKeysWithValues: memberBalances.map { ($0.0, $0.2) }
            )
            memberBalances = remoteBalances.map { balance in
                let memberID = balance.userId.uuidString
                return (memberID, balance.totalOwed, breakdowns[memberID] ?? [])
            }.sorted { $0.1 > $1.1 }
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
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

        summary += "Subtotal: \(CurrencyManager.format(subtotal, currency: currency))\n"
        summary += "Tax: \(CurrencyManager.format(tax, currency: currency))\n"
        summary += "Tip: \(CurrencyManager.format(tip, currency: currency))\n"
        if discount > 0 {
            summary += "Discount: -\(CurrencyManager.format(discount, currency: currency))\n"
        }
        summary += "Total: \(CurrencyManager.format(fullReceiptTotal, currency: currency))\n\n"

        summary += "--- Balances ---\n"
        for (member, amount, _) in memberBalances {
            if amount > 0 {
                let name = store.getGroup(id: groupId)?.members
                    .first(where: { $0.id.uuidString == member })?.displayName ?? "Member"
                summary += "\(name) owes \(CurrencyManager.format(amount, currency: currency))\n"
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
