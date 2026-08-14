import SwiftUI

struct ReceiptReviewView: View {
    let receipt: RemoteReceipt
    let groupId: UUID
    @Binding var appState: AppState

    @EnvironmentObject private var store: AppStore
    @ObservedObject private var session = SupabaseManager.shared
    @State private var review: ReceiptReview?
    @State private var isLoading = true
    @State private var isUpdating = false
    @State private var pendingSettlement: SettlementRequest?
    @State private var serviceIssueMessage: String?

    private var currentReceipt: RemoteReceipt { review?.receipt ?? receipt }
    private var isAdmin: Bool { review?.viewerIsAdmin ?? (session.currentUser?.id == receipt.adminId) }
    private var currentUserID: UUID? { session.currentUser?.id }
    private var group: GroupModel? { store.getGroup(id: groupId) }
    private var admin: GroupMemberModel? { group?.members.first(where: { $0.id == currentReceipt.adminId }) }
    private var adminRegion: AppRegion {
        admin?.regionCode.flatMap(AppRegion.init(rawValue:)) ?? RegionManager.shared.currentRegion
    }

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isLoading && review == nil {
                    Spacer()
                    ProgressView("Loading the latest receipt…")
                        .tint(DesignSystem.accentNavy)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            receiptSummary
                            if let serviceIssueMessage {
                                serviceIssueCard(serviceIssueMessage)
                            } else {
                                personalShare
                                if isAdmin { adminReview }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .refreshable { await loadReview(showError: true) }
                }
            }
        }
        .task(id: receipt.id) {
            await loadReview(showError: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await loadReview()
            }
        }
        .sheet(item: $pendingSettlement) { request in
            SettlementHandoffSheet(request: request, region: adminRegion)
        }
    }

    private var header: some View {
        HStack {
            CleaveIconButton(systemName: "chevron.left", accessibilityText: "Back to group") {
                appState = .groupDetail(group: groupId)
            }
            Spacer()
            Text(isAdmin ? "RECEIPT ADMIN" : "YOUR SHARE")
                .font(DesignSystem.labelFont(10))
                .tracking(1.4)
                .foregroundStyle(isAdmin ? DesignSystem.accentOrange : DesignSystem.accentTeal)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.white.opacity(0.8), in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.top, 58)
        .padding(.bottom, 18)
    }

    private var receiptSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(currentReceipt.title)
                .font(DesignSystem.displayFont(30))
                .foregroundStyle(.white)
            HStack {
                Label("Admin: \(admin?.preferredName ?? "Member")", systemImage: "person.badge.key.fill")
                Spacer()
                Text(CurrencyManager.shared.format(currentReceipt.total, currency: currentReceipt.currency))
                    .font(DesignSystem.displayFont(21))
            }
            .font(DesignSystem.bodyFont(13))
            .foregroundStyle(.white.opacity(0.86))
        }
        .padding(22)
        .background(DesignSystem.color(forGroupId: groupId.uuidString, in: store.groups))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func serviceIssueCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Beta service update required", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                .font(DesignSystem.titleFont(17))
                .foregroundStyle(DesignSystem.accentOrange)
            Text(message)
                .font(DesignSystem.bodyFont(14))
                .foregroundStyle(DesignSystem.inkMuted)
            Text("Your receipt is still saved. Update the backend before testing payment review or allocations.")
                .font(DesignSystem.bodyFont(13))
                .foregroundStyle(DesignSystem.inkMuted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var adminReview: some View {
        VStack(spacing: 18) {
            sectionCard(title: "Payment review", subtitle: "Confirm only after checking your payment app.") {
                let memberBalances = (review?.balances ?? []).filter { $0.userId != currentReceipt.adminId }
                if memberBalances.isEmpty {
                    Text(readyForPayments ? "No member payments are due." : "Payment review unlocks after everyone confirms their items.")
                        .emptyReviewText()
                } else {
                    ForEach(memberBalances, id: \.userId) { balance in
                        adminPaymentRow(balance)
                    }
                }
            }

            sectionCard(title: "Admin corrections", subtitle: "Members choose for themselves. Use this only to resolve mistakes or unclaimed items.") {
                ForEach(currentReceipt.items) { item in
                    allocationRow(item)
                }

                Button {
                    appState = .assignment(
                        receiptId: currentReceipt.id.uuidString,
                        group: groupId,
                        title: currentReceipt.title,
                        items: currentReceipt.items,
                        assignments: currentReceipt.assignmentMap,
                        tax: currentReceipt.taxAmount,
                        tip: currentReceipt.tipAmount,
                        discount: currentReceipt.discountAmount,
                        currency: currentReceipt.currency,
                        viewerIsAdmin: true,
                        adminOverrideMode: true
                    )
                } label: {
                    Label("Change receipt or allocations", systemImage: "slider.horizontal.3")
                }
                .primaryButton()
                .buttonStyle(PressScaleButtonStyle())
            }
        }
    }

    private var personalShare: some View {
        VStack(spacing: 18) {
            sectionCard(
                title: isAdmin ? "Your share" : "What you owe",
                subtitle: isAdmin ? "You paid the receipt; this is the part that remains yours." : "Your total updates as shared-item claims are confirmed."
            ) {
                if currentParticipant?.hasSubmitted == false {
                    Text("Choose your items before viewing your final share.")
                        .emptyReviewText()
                    Button {
                        openMyClaim()
                    } label: {
                        Label("Choose my items", systemImage: "hand.tap.fill")
                    }
                    .primaryButton()
                    .buttonStyle(PressScaleButtonStyle())
                } else if let balance = currentBalance, balance.totalOwed > 0 {
                    HStack(alignment: .firstTextBaseline) {
                        Text(CurrencyManager.shared.format(balance.totalOwed, currency: currentReceipt.currency))
                            .font(DesignSystem.displayFont(34))
                            .foregroundStyle(DesignSystem.accentNavy)
                        Spacer()
                        if isAdmin {
                            Text("RECEIPT PAYER")
                                .font(DesignSystem.labelFont(9))
                                .foregroundStyle(DesignSystem.accentTeal)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(DesignSystem.accentTeal.opacity(0.1), in: Capsule())
                        } else {
                            paymentStatusBadge(currentPayment?.status)
                        }
                    }

                    Divider().overlay(DesignSystem.hairline)
                    personalCalculation(balance)

                    if isAdmin {
                        Text("No payment action is needed—you already covered the bill.")
                            .emptyReviewText()
                    } else if !readyForPayments {
                        Label("Waiting for everyone to finish choosing", systemImage: "clock.fill")
                            .emptyReviewText()
                    } else if currentPayment == nil || currentPayment?.status == "rejected" {
                        Button(action: openPaymentHandoff) {
                            PaymentBrandButtonLabel(method: adminRegion.settlementMethod)
                        }
                        .buttonStyle(PressScaleButtonStyle())

                        Button {
                            Task { await markPaid() }
                        } label: {
                            Label(isUpdating ? "Updating…" : "I sent this payment", systemImage: "checkmark.circle.fill")
                        }
                        .secondaryReviewButton()
                        .disabled(isUpdating)
                    } else if currentPayment?.status == "pending" {
                        Text("The receipt admin will confirm after checking their payment app.")
                            .emptyReviewText()
                        Button("Undo payment mark") {
                            Task { await withdrawPaidMark() }
                        }
                        .secondaryReviewButton()
                        .disabled(isUpdating)
                    } else {
                        Label("Confirmed by the receipt admin", systemImage: "checkmark.seal.fill")
                            .font(DesignSystem.titleFont(14))
                            .foregroundStyle(DesignSystem.accentTeal)
                    }

                    if !hasConfirmedPayment {
                        Button {
                            openMyClaim()
                        } label: {
                            Label("Change my items", systemImage: "checklist")
                        }
                        .secondaryReviewButton()
                    }
                } else {
                    Label("Nothing assigned to you", systemImage: "checkmark.circle.fill")
                        .font(DesignSystem.titleFont(16))
                        .foregroundStyle(DesignSystem.accentTeal)
                    if !hasConfirmedPayment {
                        Button {
                            openMyClaim()
                        } label: {
                            Label("Change my items", systemImage: "checklist")
                        }
                        .secondaryReviewButton()
                    }
                }
            }

        }
    }

    @ViewBuilder
    private func personalCalculation(_ balance: RemoteBalance) -> some View {
        VStack(spacing: 10) {
            ForEach(balance.items) { item in
                calculationRow(item.name, amount: item.amount)
            }
            Divider().overlay(DesignSystem.hairline)
            calculationRow("Items subtotal", amount: balance.itemsTotal)
            if balance.taxShare > 0 { calculationRow("Tax share", amount: balance.taxShare) }
            if balance.tipShare > 0 { calculationRow("Tip share", amount: balance.tipShare) }
            if balance.discountShare > 0 { calculationRow("Discount share", amount: -balance.discountShare) }
            calculationRow("Total", amount: balance.totalOwed, emphasized: true)
        }
    }

    private func calculationRow(_ label: String, amount: Double, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? DesignSystem.titleFont(15) : DesignSystem.bodyFont(13))
            Spacer()
            Text(CurrencyManager.shared.format(amount, currency: currentReceipt.currency))
                .font(emphasized ? DesignSystem.titleFont(15) : DesignSystem.bodyFont(13))
                .foregroundStyle(emphasized ? DesignSystem.ink : DesignSystem.inkMuted)
        }
    }

    private var currentBalance: RemoteBalance? {
        guard let currentUserID else { return nil }
        return review?.balances.first(where: { $0.userId == currentUserID })
    }

    private var currentPayment: RemoteSettlement? {
        guard let currentUserID else { return nil }
        return review?.payments.first(where: { $0.fromUserId == currentUserID })
    }

    private var currentParticipant: RemoteReceiptParticipant? {
        guard let currentUserID else { return nil }
        return currentReceipt.participants?.first(where: { $0.userId == currentUserID })
    }

    private var readyForPayments: Bool {
        let participants = currentReceipt.participants ?? []
        return !participants.isEmpty
            && participants.allSatisfy(\.hasSubmitted)
            && currentReceipt.items.allSatisfy { !($0.assignedUserIds ?? []).isEmpty }
    }

    private var hasConfirmedPayment: Bool {
        review?.payments.contains(where: { $0.status == "confirmed" }) == true
    }

    private func openMyClaim() {
        appState = .assignment(
            receiptId: currentReceipt.id.uuidString,
            group: groupId,
            title: currentReceipt.title,
            items: currentReceipt.items,
            assignments: currentReceipt.assignmentMap,
            tax: currentReceipt.taxAmount,
            tip: currentReceipt.tipAmount,
            discount: currentReceipt.discountAmount,
            currency: currentReceipt.currency,
            viewerIsAdmin: isAdmin,
            adminOverrideMode: false
        )
    }

    private func adminPaymentRow(_ balance: RemoteBalance) -> some View {
        let member = group?.members.first(where: { $0.id == balance.userId })
        let payment = review?.payments.first(where: { $0.fromUserId == balance.userId })
        return VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(member?.preferredName ?? "Member")
                        .font(DesignSystem.titleFont(16))
                    Text(CurrencyManager.shared.format(balance.totalOwed, currency: currentReceipt.currency))
                        .font(DesignSystem.bodyFont(14))
                        .foregroundStyle(DesignSystem.inkMuted)
                }
                Spacer()
                paymentStatusBadge(payment?.status)
            }
            if let payment, payment.status == "pending" {
                HStack(spacing: 10) {
                    Button("Reject") { Task { await reviewPayment(payment, status: "rejected") } }
                        .secondaryReviewButton()
                    Button("Confirm") { Task { await reviewPayment(payment, status: "confirmed") } }
                        .primaryCompactReviewButton()
                }
                .disabled(isUpdating)
            }
        }
        .padding(.vertical, 8)
    }

    private func allocationRow(_ item: ReceiptItem) -> some View {
        let names = (item.assignedUserIds ?? []).compactMap { id in
            group?.members.first(where: { $0.id == id })?.preferredName
        }
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(DesignSystem.titleFont(15))
                Text(names.isEmpty ? "Unassigned" : names.joined(separator: ", "))
                    .font(DesignSystem.bodyFont(12))
                    .foregroundStyle(names.isEmpty ? DesignSystem.accentOrange : DesignSystem.inkMuted)
            }
            Spacer()
            Text(CurrencyManager.shared.format(item.price, currency: currentReceipt.currency))
                .font(DesignSystem.bodyFont(14))
        }
        .padding(.vertical, 6)
    }

    private func paymentStatusBadge(_ status: String?) -> some View {
        let label: String
        let color: Color
        switch status {
        case "pending": (label, color) = ("Marked paid", DesignSystem.accentOrange)
        case "confirmed": (label, color) = ("Confirmed", DesignSystem.accentTeal)
        case "rejected": (label, color) = ("Needs attention", .red)
        default: (label, color) = ("Not marked", DesignSystem.inkMuted)
        }
        return Text(label)
            .font(DesignSystem.labelFont(10))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(DesignSystem.displayFont(22))
            Text(subtitle)
                .font(DesignSystem.bodyFont(13))
                .foregroundStyle(DesignSystem.inkMuted)
            content()
        }
        .foregroundStyle(DesignSystem.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(DesignSystem.hairline, lineWidth: 1))
    }

    @MainActor
    private func loadReview(showError: Bool = false) async {
        defer { isLoading = false }
        do {
            let latest = try await CleaveAPI.shared.fetchReceiptReview(receiptID: receipt.id.uuidString)
            serviceIssueMessage = nil
            if latest != review { review = latest }
        } catch CleaveAPI.APIError.serviceUpdateRequired {
            serviceIssueMessage = CleaveAPI.APIError.serviceUpdateRequired.localizedDescription
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            if showError { ErrorManager.shared.showError(error.localizedDescription) }
        }
    }

    private func openPaymentHandoff() {
        guard let balance = currentBalance else { return }
        pendingSettlement = SettlementRequest(
            recipientName: admin?.preferredName ?? "the receipt admin",
            venmoUsername: admin?.venmoUsername,
            upiID: admin?.upiId,
            aaniID: admin?.aaniId,
            amount: balance.totalOwed,
            currency: currentReceipt.currency,
            note: "Cleave - \(currentReceipt.title)"
        )
    }

    @MainActor
    private func markPaid() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            _ = try await CleaveAPI.shared.markReceiptPaid(receiptID: receipt.id.uuidString)
            await loadReview()
            HapticsManager.shared.playNotification(type: .success)
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }

    @MainActor
    private func withdrawPaidMark() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            try await CleaveAPI.shared.withdrawReceiptPaidMark(receiptID: receipt.id.uuidString)
            await loadReview()
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }

    @MainActor
    private func reviewPayment(_ payment: RemoteSettlement, status: String) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            _ = try await CleaveAPI.shared.reviewPayment(
                receiptID: receipt.id.uuidString,
                paymentID: payment.id,
                status: status
            )
            await loadReview()
            HapticsManager.shared.playNotification(type: .success)
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }
}

private extension View {
    func emptyReviewText() -> some View {
        font(DesignSystem.bodyFont(13))
            .foregroundStyle(DesignSystem.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    func secondaryReviewButton() -> some View {
        font(DesignSystem.titleFont(14))
            .foregroundStyle(DesignSystem.accentNavy)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(DesignSystem.accentNavy.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    func primaryCompactReviewButton() -> some View {
        font(DesignSystem.titleFont(14))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(DesignSystem.accentNavy, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
