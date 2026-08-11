import SwiftUI

struct BespokeAssignmentView: View {
    let receiptId: String
    let groupId: UUID
    @Binding var appState: AppState
    var namespace: Namespace.ID

    let initialTitle: String
    let initialItems: [ReceiptItem]
    let initialAssignments: [String: Set<String>]
    let initialTax: Double
    let initialTip: Double
    let initialDiscount: Double
    let currency: Currency

    @EnvironmentObject var store: AppStore

    @State private var title: String
    @State private var items: [ReceiptItem]
    @State private var tax: Double
    @State private var tip: Double
    @State private var discount: Double

    let memberColors: [Color] = [
        DesignSystem.accentNavy,
        DesignSystem.accentTeal,
        DesignSystem.accentSand,
        DesignSystem.accentPeach
    ]

    init(receiptId: String, groupId: UUID, appState: Binding<AppState>, namespace: Namespace.ID, initialTitle: String, initialItems: [ReceiptItem], initialAssignments: [String: Set<String>] = [:], initialTax: Double, initialTip: Double, initialDiscount: Double, currency: Currency) {
        self.receiptId = receiptId
        self.groupId = groupId
        self._appState = appState
        self.namespace = namespace
        self.initialTitle = initialTitle
        self.initialItems = initialItems
        self.initialAssignments = initialAssignments
        self.initialTax = initialTax
        self.initialTip = initialTip
        self.initialDiscount = initialDiscount
        self.currency = currency

        self._title = State(initialValue: initialTitle)
        self._items = State(initialValue: initialItems)
        self._assignments = State(initialValue: initialAssignments)
        self._tax = State(initialValue: initialTax)
        self._tip = State(initialValue: initialTip)
        self._discount = State(initialValue: initialDiscount)
    }

    // State to track which members are assigned to which item id (allows multiple)
    @State private var assignments: [String: Set<String>] = [:]

    // Editing State
    enum EditTarget: Equatable { case item(Int), tax, tip }
    @State private var editingTarget: EditTarget? = nil
    @State private var editName: String = ""
    @State private var editPrice: String = ""

    // Alert State
    @State private var showingUnassignedAlert = false
    @State private var isSaving = false

    var groupMembers: [GroupMemberModel] {
        store.getGroup(id: groupId)?.members ?? []
    }


    private var subtotal: Double {
        items.reduce(0) { $0 + $1.price }
    }

    private var total: Double {
        subtotal + tax + tip - discount
    }

    private var assignedItemCount: Int {
        items.filter { !(assignments[$0.id] ?? []).isEmpty }.count
    }

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    CleaveIconButton(systemName: "xmark", accessibilityText: "Close receipt") {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .groupDetail(group: groupId)
                        }
                    }
                    Spacer()

                    Text("\(assignedItemCount)/\(items.count) ASSIGNED")
                        .font(DesignSystem.labelFont(10))
                        .tracking(1.2)
                        .foregroundStyle(assignedItemCount == items.count ? DesignSystem.accentTeal : DesignSystem.inkMuted)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(DesignSystem.surface.opacity(0.78))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 22)
                .padding(.top, 58)

                VStack(alignment: .leading, spacing: 6) {
                    Text("SPLIT THIS RECEIPT")
                        .font(DesignSystem.labelFont(10))
                        .tracking(1.8)
                        .foregroundStyle(DesignSystem.accentOrange)

                    HStack(spacing: 8) {
                        TextField(
                            "Receipt title",
                            text: $title,
                            prompt: Text("Receipt title").foregroundStyle(DesignSystem.ink.opacity(0.34))
                        )
                            .font(DesignSystem.displayFont(31))
                            .foregroundStyle(DesignSystem.ink)
                            .tint(DesignSystem.accentTeal)
                            .lineLimit(1)

                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DesignSystem.inkMuted)
                    }

                    Text("Tap everyone who shared each item.")
                        .font(DesignSystem.bodyFont(14))
                        .foregroundStyle(DesignSystem.inkMuted)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        ForEach(items.indices, id: \.self) { index in
                            receiptItemRow(index: index)
                        }

                        Divider().overlay(Color.white.opacity(0.28)).padding(.vertical, 5)

                        nonAssignableRow(title: "Tax", value: tax, target: .tax)
                        nonAssignableRow(title: "Tip", value: tip, target: .tip)

                        VStack(spacing: 10) {
                            HStack {
                                Text("Subtotal")
                                    .font(DesignSystem.bodyFont(14))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text(CurrencyManager.format(subtotal, currency: currency))
                                    .font(DesignSystem.bodyFont(14))
                                    .foregroundColor(.white.opacity(0.8))
                            }

                            HStack {
                                Text("Total")
                                    .font(DesignSystem.titleFont(19))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(CurrencyManager.format(total, currency: currency))
                                    .font(DesignSystem.displayFont(20))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(20)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(18)
                    .padding(.bottom, 8)
                    .background(DesignSystem.color(forGroupId: groupId.uuidString, in: store.groups))
                    .clipShape(ReceiptCardShape())
                    .padding(.horizontal, 14)
                    .padding(.bottom, 22)
                    .shadow(color: DesignSystem.color(forGroupId: groupId.uuidString, in: store.groups).opacity(0.22), radius: 18, y: 10)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: handleCalculateBalances) {
                    HStack(spacing: 10) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isSaving ? "Saving…" : "See balances")
                        if !isSaving {
                            Image(systemName: "arrow.right")
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

            // Custom Edit Modal Overlay
            if let target = editingTarget {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { editingTarget = nil }
                    }

                VStack(spacing: 20) {
                    Text(targetTitle)
                        .font(DesignSystem.displayFont(24))
                        .foregroundColor(.white)

                    if case .item(_) = target {
                        TextField("Item name", text: $editName, prompt: Text("Item name").foregroundStyle(.white.opacity(0.48)))
                            .font(DesignSystem.bodyFont(16))
                            .padding()
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .tint(.white)
                    }

                    HStack {
                        Text(CurrencyManager.shared.currentCurrency.symbol)
                            .font(DesignSystem.labelFont(12))
                            .foregroundColor(.white.opacity(0.7))
                        TextField("Amount", text: $editPrice, prompt: Text("Amount").foregroundStyle(.white.opacity(0.48)))
                            .font(DesignSystem.bodyFont(16))
                            .keyboardType(.decimalPad)
                            .foregroundColor(.white)
                            .tint(.white)
                    }
                    .padding()
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12)

                    HStack(spacing: 15) {
                        Button("Cancel") {
                            withAnimation { editingTarget = nil }
                        }
                        .font(DesignSystem.titleFont(15))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                        .foregroundColor(.white)

                        Button("Save") {
                            saveEdit()
                            withAnimation { editingTarget = nil }
                        }
                        .font(DesignSystem.titleFont(15))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.accentNavy)
                        .cornerRadius(12)
                        .foregroundColor(.white)
                    }
                }
                .padding(30)
                .background(DesignSystem.color(forGroupId: groupId.uuidString, in: store.groups))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: DesignSystem.color(forGroupId: groupId.uuidString, in: store.groups).opacity(0.3), radius: 25, y: 15)
                .padding(.horizontal, 40)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .alert("Unassigned Items", isPresented: $showingUnassignedAlert) {
            Button("Force Split Equally") {
                forceSplitUnassignedItems()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("There are items with no assigned members. Would you like to split them equally among everyone?")
        }
    }

    private func receiptItemRow(index: Int) -> some View {
        let itemId = items[index].id
        let assignedMembers = assignments[itemId] ?? []
        let isAssigned = !assignedMembers.isEmpty

        return VStack(spacing: 16) {
            HStack {
                Text(items[index].name)
                    .font(DesignSystem.titleFont(17))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Spacer()

                HStack(spacing: 8) {
                    Text(CurrencyManager.format(items[index].price, currency: currency))
                        .font(DesignSystem.titleFont(15))
                        .foregroundColor(.white.opacity(0.9))

                    Button(action: {
                        openEditModal(for: .item(index))
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 20))
                    }
                }
            }

            // Inline Member Selectors
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(Array(groupMembers.enumerated()), id: \.element.id) { _, member in
                        let memberID = member.id.uuidString
                        let isSelected = assignedMembers.contains(memberID)
                        let fgColor: Color = isSelected ? DesignSystem.color(forGroupId: groupId.uuidString, in: store.groups) : .white

                        Button(action: {
                            HapticsManager.shared.playImpact(style: .medium)

                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                if assignments[itemId] == nil {
                                    assignments[itemId] = []
                                }

                                if isSelected {
                                    assignments[itemId]?.remove(memberID)
                                } else {
                                    assignments[itemId]?.insert(memberID)
                                }

                            }
                        }) {
                            HStack(spacing: 7) {
                                Text(String(member.displayName.prefix(1)))
                                    .font(DesignSystem.labelFont(11))
                                    .frame(width: 26, height: 26)
                                    .background(isSelected ? fgColor.opacity(0.12) : Color.white.opacity(0.13))
                                    .clipShape(Circle())
                                Text(member.displayName)
                                    .font(DesignSystem.titleFont(13))
                                    .lineLimit(1)
                            }
                            .foregroundColor(fgColor)
                            .padding(.leading, 6)
                            .padding(.trailing, 11)
                            .frame(height: 40)
                            .background(isSelected ? .white : Color.white.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.white : Color.white.opacity(0.34), lineWidth: 1)
                            )
                            .shadow(color: isSelected ? Color.black.opacity(0.16) : .clear, radius: 6, y: 3)
                        }
                    }
                }
                .padding(.horizontal, 4) // Prevent clipping of the first scaled/stroked element
                .padding(.vertical, 8) // Give breathing room for shadow
            }
        }
        .padding(17)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(isAssigned ? 0.3 : 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isAssigned ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private func nonAssignableRow(title: String, value: Double, target: EditTarget) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.titleFont(16))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 8) {
                Text(CurrencyManager.format(value, currency: currency))
                    .font(DesignSystem.titleFont(15))
                    .foregroundColor(.white.opacity(0.9))

                Button(action: {
                    openEditModal(for: target)
                }) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 20))
                }
            }
        }
        .padding(20)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var targetTitle: String {
        switch editingTarget {
        case .item(_): return "Edit Item"
        case .tax: return "Edit Tax"
        case .tip: return "Edit Tip"
        case .none: return ""
        }
    }

    private func openEditModal(for target: EditTarget) {
        editingTarget = target
        switch target {
        case .item(let index):
            editName = items[index].name
            editPrice = String(format: "%.2f", items[index].price)
        case .tax:
            editPrice = String(format: "%.2f", tax)
        case .tip:
            editPrice = String(format: "%.2f", tip)
        }
        withAnimation { }
    }

    private func saveEdit() {
        let amount = Double(editPrice) ?? 0.0
        switch editingTarget {
        case .item(let index):
            items[index] = ReceiptItem(id: items[index].id, name: editName, price: amount)
        case .tax:
            tax = amount
        case .tip:
            tip = amount
        case .none: break
        }
    }

    private func handleCalculateBalances() {
        let unassignedExists = items.contains { item in
            let members = assignments[item.id] ?? []
            return members.isEmpty
        }

        if unassignedExists {
            showingUnassignedAlert = true
        } else {
            Task { await saveAndProceed() }
        }
    }

    private func forceSplitUnassignedItems() {
        let allMembers = Set(groupMembers.map { $0.id.uuidString })
        for item in items {
            let members = assignments[item.id] ?? []
            if members.isEmpty {
                assignments[item.id] = allMembers
            }
        }

        Task { await saveAndProceed() }
    }

    private func proceedToBalances() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            appState = .balances(receiptId: receiptId, group: groupId, title: title, items: items, assignments: assignments, tax: tax, tip: tip, discount: discount, currency: currency)
        }
    }

    private func saveAndProceed() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        if let group = store.getGroup(id: groupId), !group.isCollaborative,
           let receiptUUID = UUID(uuidString: receiptId) {
            store.updateLocalReceipt(
                id: receiptUUID,
                groupID: groupId,
                title: title,
                items: items,
                tax: tax,
                tip: tip,
                discount: discount
            )
            proceedToBalances()
            return
        }
        do {
            _ = try await CleaveAPI.shared.updateReceipt(
                receiptID: receiptId,
                title: title,
                items: items,
                tax: tax,
                tip: tip,
                discount: discount
            )
            let completeAssignments = Dictionary(
                uniqueKeysWithValues: items.map { item in
                    (item.id, assignments[item.id] ?? [])
                }
            )
            try await CleaveAPI.shared.assignItems(
                receiptID: receiptId,
                assignments: completeAssignments
            )
            proceedToBalances()
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }
}
