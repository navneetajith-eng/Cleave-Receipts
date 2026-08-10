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

    var body: some View {
        NavigationView {
            ZStack {
                DesignSystem.canvasBeige.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Receipt Details")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.black.opacity(0.5))

                            VStack(spacing: 16) {
                                TextField("Receipt Title", text: $title)
                                    .padding()
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(12)

                                HStack(spacing: 16) {
                                    TextField("Tax", text: $tax)
                                        .keyboardType(.decimalPad)
                                        .padding()
                                        .background(Color.black.opacity(0.05))
                                        .cornerRadius(12)

                                    TextField("Tip", text: $tip)
                                        .keyboardType(.decimalPad)
                                        .padding()
                                        .background(Color.black.opacity(0.05))
                                        .cornerRadius(12)
                                }
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(16)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Items")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.black.opacity(0.5))
                                Spacer()
                                Button(action: {
                                    withAnimation {
                                        manualItems.append(ManualItem())
                                    }
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(DesignSystem.accentTeal)
                                        .font(.title2)
                                }
                            }

                            VStack(spacing: 16) {
                                ForEach($manualItems) { $item in
                                    HStack {
                                        TextField("Item Name", text: $item.name)
                                        .padding()
                                        .background(Color.black.opacity(0.05))
                                        .cornerRadius(12)

                                        TextField("Price", value: $item.price, format: .number)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 80)
                                        .padding()
                                        .background(Color.black.opacity(0.05))
                                        .cornerRadius(12)

                                        if manualItems.count > 1 {
                                            Button(action: {
                                                withAnimation {
                                                    manualItems.removeAll(where: { $0.id == item.id })
                                                }
                                            }) {
                                                Image(systemName: "trash.fill")
                                                    .foregroundColor(.red.opacity(0.7))
                                            }
                                            .padding(.leading, 8)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(16)
                        }

                        Button(action: {
                            HapticsManager.shared.playImpact(style: .medium)
                            let taxVal = Double(tax) ?? 0.0
                            let tipVal = Double(tip) ?? 0.0
                            let validItems = manualItems.filter { !$0.name.isEmpty }
                            let items = validItems.map { ReceiptItem(id: UUID().uuidString, name: $0.name, price: $0.price ?? 0.0) }
                            isSaving = true
                            Task {
                                do {
                                    let receipt: RemoteReceipt
                                    if let group = store.getGroup(id: groupId), !group.isCollaborative {
                                        guard let userID = SupabaseManager.shared.currentUser?.id else {
                                            throw CleaveAPI.APIError.unauthorized
                                        }
                                        receipt = RemoteReceipt(
                                            id: UUID(),
                                            groupId: groupId,
                                            title: title.isEmpty ? "Manual Entry" : title,
                                            adminId: userID,
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
                                            discount: 0
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
                                                discount: receipt.discountAmount
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
                        }) {
                            Group {
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Continue to Split")
                                }
                            }
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(DesignSystem.accentNavy)
                            .clipShape(Capsule())
                        }
                        .disabled(isSaving || manualItems.filter { !$0.name.isEmpty }.isEmpty)
                        .padding(.top, 20)
                    }
                    .padding(30)
                }
            }
            .navigationTitle("Manual Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(DesignSystem.accentNavy)
                }
            }
        }
    }
}
