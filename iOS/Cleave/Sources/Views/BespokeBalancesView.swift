import SwiftUI
import PhotosUI

struct BreakdownItem: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
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
    @Binding var appState: AppState
    var namespace: Namespace.ID

    @EnvironmentObject var store: AppStore
    @State private var memberBalances: [(String, Double, [BreakdownItem])] = []

    // Memories
    @State private var rating: Int = 0
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedPhotos: [Data] = []
    @State private var isSaving = false

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .assignment(receiptId: receiptId, group: groupId, title: title, items: items, assignments: assignments, tax: tax, tip: tip, discount: discount)
                        }
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.black.opacity(0.7))
                    }
                    Spacer()
                    Button(action: {
                        shareSummary()
                    }) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.black.opacity(0.7))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 60)

                Text("Balances")
                    .font(.system(size: 48, weight: .light, design: .serif))
                    .foregroundColor(.black)
                    .padding(.horizontal, 30)
                    .padding(.top, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Finances Receipt Card
                        VStack(spacing: 0) {
                            masterSummaryCard()

                            Text("Individual Breakdown")
                                .font(.system(.title3, design: .serif))
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
                            Text("Rate your experience at '\(title)'!")
                                .font(.system(.title3, design: .serif))
                                .foregroundColor(.white)

                            // Star Rating
                            HStack(spacing: 15) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.system(size: 30))
                                        .foregroundColor(star <= rating ? .white : .white.opacity(0.3))
                                        .onTapGesture {
                                            withAnimation { rating = star }
                                        }
                                }
                            }

                            Text("Upload your memories at '\(title)'")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.top, 10)

                            // Photos
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 5, matching: .images) {
                                        VStack {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 24))
                                            Text("Add Photos")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.white.opacity(0.8))
                                        .frame(width: 100, height: 100)
                                        .background(Color.white.opacity(0.15))
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
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 150) // Space for button
                    }
                }
            }

            // Floating Action Button
            VStack {
                Spacer()
                Button(action: {
                    Task {
                        await saveReceiptAndUploadPhotos()
                    }
                }) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Save Receipt")
                    }
                }
                .primaryButton()
                .disabled(isSaving)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .task {
            calculateBalances()
            if store.getGroup(id: groupId)?.isCollaborative == true {
                async let balances: Void = loadAuthoritativeBalances()
                async let experience: Void = loadSavedExperience()
                _ = await (balances, experience)
            }
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
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(CurrencyManager.shared.format(subtotal))
                    .foregroundColor(.white.opacity(0.8))
            }

            if tax > 0 {
                HStack {
                    Text("Tax")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(CurrencyManager.shared.format(tax))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            if tip > 0 {
                HStack {
                    Text("Tip")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(CurrencyManager.shared.format(tip))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            Divider().background(Color.white.opacity(0.3)).padding(.vertical, 4)

            HStack {
                Text("Total Allocated")
                    .font(.system(.title3, design: .serif))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Text(CurrencyManager.shared.format(fullReceiptTotal))
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
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
                            .font(.system(size: 20, design: .serif))
                            .foregroundColor(.white)
                    )

                Text(displayName)
                    .font(.system(.title3, design: .serif))
                    .foregroundColor(.white)
                    .padding(.leading, 10)

                Spacer()

                Text(CurrencyManager.shared.format(total))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(24)

            // Settlement button
            if total > 0 {
                let isGroupCollaborative = store.getGroup(id: groupId)?.isCollaborative ?? false
                let unassignedExists = items.contains { (assignments[$0.id] ?? []).isEmpty }
                let isLocked = isGroupCollaborative && unassignedExists

                Button(action: {
                    if isLocked { return }
                    let note = "Cleave - \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let amountStr = String(format: "%.2f", total)
                    if let url = URL(string: "venmo://paycharge?txn=pay&amount=\(amountStr)&note=\(note)") {
                        if UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        } else {
                            // Fallback to web
                            if let webUrl = URL(string: "https://venmo.com/?txn=pay&amount=\(amountStr)&note=\(note)") {
                                UIApplication.shared.open(webUrl)
                            }
                        }
                    }
                }) {
                    HStack {
                        if isLocked {
                            Image(systemName: "lock.fill")
                            Text("Waiting for everyone...")
                        } else {
                            Image(systemName: "v.square.fill")
                            Text("Settle via Venmo")
                        }
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundColor(isLocked ? .white.opacity(0.6) : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isLocked ? Color.gray.opacity(0.5) : Color.blue.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isLocked)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            if !breakdown.isEmpty {
                Divider().background(Color.white.opacity(0.3)).padding(.horizontal, 24)

                VStack(spacing: 8) {
                    ForEach(breakdown, id: \.id) { item in
                        HStack {
                            Text(item.name)
                                .font(.system(.subheadline, design: .serif))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Text(CurrencyManager.shared.format(item.amount))
                                .font(.system(.subheadline, design: .rounded))
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

    private func shareSummary() {
        var summary = "Cleave Split: \(title)\n\n"

        let subtotal = items.reduce(0) { $0 + $1.price }

        summary += "Subtotal: \(CurrencyManager.shared.format(subtotal))\n"
        summary += "Tax: \(CurrencyManager.shared.format(tax))\n"
        summary += "Tip: \(CurrencyManager.shared.format(tip))\n"
        if discount > 0 {
            summary += "Discount: -\(CurrencyManager.shared.format(discount))\n"
        }
        summary += "Total: \(CurrencyManager.shared.format(fullReceiptTotal))\n\n"

        summary += "--- Balances ---\n"
        for (member, amount, _) in memberBalances {
            if amount > 0 {
                let name = store.getGroup(id: groupId)?.members
                    .first(where: { $0.id.uuidString == member })?.displayName ?? "Member"
                summary += "\(name) owes \(CurrencyManager.shared.format(amount))\n"
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
