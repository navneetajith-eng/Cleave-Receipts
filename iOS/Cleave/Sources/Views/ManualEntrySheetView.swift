import SwiftUI

struct ManualItem: Identifiable {
    let id = UUID()
    var name: String = ""
    var price: Double? = nil
}

struct ManualEntrySheetView: View {
    @Binding var isPresented: Bool
    @Binding var appState: AppState
    let groupId: UUID
    @EnvironmentObject private var store: AppStore

    @State private var title: String = ""
    @State private var tax: String = ""
    @State private var tip: String = ""

    @State private var manualItems: [ManualItem] = [ManualItem()]
    @State private var isSaving = false

    private var canContinue: Bool {
        !isSaving && manualItems.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.canvasBeige.ignoresSafeArea()

                VStack {
                    HStack {
                        Spacer()
                        CleaveReceiptWatermark(color: DesignSystem.accentTeal)
                            .rotationEffect(.degrees(8))
                            .offset(x: 18, y: 10)
                    }
                    Spacer()
                    HStack {
                        CleaveReceiptWatermark(color: DesignSystem.accentOrange)
                            .rotationEffect(.degrees(-9))
                            .offset(x: -18, y: 12)
                        Spacer()
                    }
                }
                .opacity(0.52)
                .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        CleaveSectionHeading(
                            "Add the details",
                            eyebrow: "Manual receipt",
                            detail: "Just the essentials. You can edit everything on the next screen."
                        )

                        receiptDetailsCard
                        itemsSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: saveAndContinue) {
                    HStack(spacing: 10) {
                        if isSaving { ProgressView().tint(.white) }
                        Text(isSaving ? "Building receipt…" : "Continue to split")
                        if !isSaving {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .black))
                        }
                    }
                }
                .primaryButton()
                .buttonStyle(PressScaleButtonStyle())
                .disabled(!canContinue)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Manual receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(DesignSystem.titleFont(16))
                    .foregroundStyle(DesignSystem.ink)
                }
            }
            .toolbarBackground(DesignSystem.canvasBeige, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .preferredColorScheme(.light)
    }

    private var receiptDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RECEIPT")
                .font(DesignSystem.labelFont(10))
                .tracking(1.7)
                .foregroundStyle(DesignSystem.inkMuted)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(DesignSystem.labelFont(12))
                    .foregroundStyle(DesignSystem.inkMuted)
                TextField(
                    "Dinner, market, coffee…",
                    text: $title,
                    prompt: Text("Dinner, market, coffee…").foregroundStyle(DesignSystem.ink.opacity(0.34))
                )
                    .font(DesignSystem.bodyFont(17))
                    .foregroundStyle(DesignSystem.ink)
                    .tint(DesignSystem.accentTeal)
                    .padding(.horizontal, 15)
                    .frame(height: 54)
                    .background(DesignSystem.fieldSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 12) {
                amountField(label: "Tax", value: $tax)
                amountField(label: "Tip", value: $tip)
            }
        }
        .padding(20)
        .background(DesignSystem.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(DesignSystem.hairline, lineWidth: 1))
        .shadow(color: DesignSystem.ink.opacity(0.06), radius: 18, y: 8)
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ITEMS")
                        .font(DesignSystem.labelFont(10))
                        .tracking(1.7)
                        .foregroundStyle(DesignSystem.accentOrange)
                    Text("What was ordered?")
                        .font(DesignSystem.titleFont(21))
                        .foregroundStyle(DesignSystem.ink)
                }
                Spacer()
                Button {
                    HapticsManager.shared.playImpact(style: .light)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        manualItems.append(ManualItem())
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(DesignSystem.titleFont(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(DesignSystem.accentTeal)
                        .clipShape(Capsule())
                }
                .buttonStyle(PressScaleButtonStyle())
            }

            VStack(spacing: 10) {
                ForEach(manualItems.indices, id: \.self) { index in
                    itemRow(index: index)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private func itemRow(index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(DesignSystem.labelFont(12))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(index.isMultiple(of: 2) ? DesignSystem.accentOrange : DesignSystem.accentTeal)
                .clipShape(Circle())

            TextField(
                "Item",
                text: $manualItems[index].name,
                prompt: Text("Item").foregroundStyle(DesignSystem.ink.opacity(0.34))
            )
                .font(DesignSystem.bodyFont(16))
                .foregroundStyle(DesignSystem.ink)
                .tint(DesignSystem.accentTeal)

            HStack(spacing: 4) {
                Text(CurrencyManager.shared.currentCurrency.symbol)
                    .font(DesignSystem.labelFont(11))
                    .foregroundStyle(DesignSystem.inkMuted)
                TextField(
                    "0.00",
                    value: $manualItems[index].price,
                    format: .number.precision(.fractionLength(0...2)),
                    prompt: Text("0.00").foregroundStyle(DesignSystem.ink.opacity(0.34))
                )
                    .font(DesignSystem.titleFont(15))
                    .foregroundStyle(DesignSystem.ink)
                    .tint(DesignSystem.accentTeal)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            .frame(width: 92)

            if manualItems.count > 1 {
                Button {
                    HapticsManager.shared.playImpact(style: .light)
                    _ = withAnimation(.easeOut(duration: 0.2)) {
                        manualItems.remove(at: index)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignSystem.inkMuted)
                        .frame(width: 30, height: 30)
                        .background(DesignSystem.fieldSurface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Remove item \(index + 1)")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
        .background(DesignSystem.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(DesignSystem.hairline, lineWidth: 1))
    }

    private func amountField(label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(DesignSystem.labelFont(12))
                .foregroundStyle(DesignSystem.inkMuted)
            HStack(spacing: 5) {
                Text(CurrencyManager.shared.currentCurrency.symbol)
                    .font(DesignSystem.labelFont(11))
                    .foregroundStyle(DesignSystem.inkMuted)
                TextField(
                    "0.00",
                    text: value,
                    prompt: Text("0.00").foregroundStyle(DesignSystem.ink.opacity(0.34))
                )
                    .font(DesignSystem.bodyFont(16))
                    .foregroundStyle(DesignSystem.ink)
                    .keyboardType(.decimalPad)
                    .tint(DesignSystem.accentTeal)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(DesignSystem.fieldSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private func saveAndContinue() {
        guard canContinue else { return }
        HapticsManager.shared.playImpact(style: .medium)
        let taxVal = Double(tax) ?? 0.0
        let tipVal = Double(tip) ?? 0.0
        let validItems = manualItems.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let items = validItems.map {
            ReceiptItem(id: UUID().uuidString, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), price: $0.price ?? 0.0)
        }
        isSaving = true
        Task {
            do {
                let receipt: RemoteReceipt
                if let group = store.getGroup(id: groupId), !group.isCollaborative {
                    guard let userID = DemoMode.effectiveUserID else {
                        throw CleaveAPI.APIError.unauthorized
                    }
                    receipt = RemoteReceipt(
                        id: UUID(),
                        groupId: groupId,
                        title: title.isEmpty ? "Manual Entry" : title,
                        adminId: userID,
                        currencyCode: CurrencyManager.shared.currentCurrency.rawValue,
                        taxAmount: taxVal,
                        tipAmount: tipVal,
                        discountAmount: 0,
                        imageUrl: nil,
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        items: items
                    )
                    await MainActor.run { store.saveLocalReceipt(receipt) }
                } else {
                    receipt = try await CleaveAPI.shared.createManualReceipt(
                        groupID: groupId,
                        title: title.isEmpty ? "Manual Entry" : title,
                        items: items,
                        tax: taxVal,
                        tip: tipVal,
                        discount: 0,
                        currency: CurrencyManager.shared.currentCurrency
                    )
                }
                await MainActor.run {
                    isPresented = false
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
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
            } catch {
                await MainActor.run {
                    isSaving = false
                    ErrorManager.shared.showError(error.localizedDescription)
                }
            }
        }
    }
}
