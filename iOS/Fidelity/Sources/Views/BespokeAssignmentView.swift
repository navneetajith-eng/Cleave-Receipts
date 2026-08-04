import SwiftUI

struct BespokeAssignmentView: View {
    let groupName: String
    @Binding var appState: AppState
    var namespace: Namespace.ID
    
    let initialTitle: String
    let initialItems: [(String, Double)]
    let initialTax: Double
    let initialTip: Double
    
    @EnvironmentObject var store: AppStore
    
    @State private var title: String
    @State private var items: [(String, Double)]
    @State private var tax: Double
    @State private var tip: Double
    
    let memberColors: [Color] = [
        DesignSystem.accentSage,
        DesignSystem.accentDustyRose,
        DesignSystem.accentMustard,
        DesignSystem.accentSlate
    ]
    
    init(groupName: String, appState: Binding<AppState>, namespace: Namespace.ID, initialTitle: String, initialItems: [(String, Double)], initialTax: Double, initialTip: Double) {
        self.groupName = groupName
        self._appState = appState
        self.namespace = namespace
        self.initialTitle = initialTitle
        self.initialItems = initialItems
        self.initialTax = initialTax
        self.initialTip = initialTip
        
        self._title = State(initialValue: initialTitle)
        self._items = State(initialValue: initialItems)
        self._tax = State(initialValue: initialTax)
        self._tip = State(initialValue: initialTip)
    }
    
    // State to track which members are assigned to which item index (allows multiple)
    @State private var assignments: [Int: Set<String>] = [:]
    
    // Editing State
    enum EditTarget: Equatable { case item(Int), tax, tip }
    @State private var editingTarget: EditTarget? = nil
    @State private var editName: String = ""
    @State private var editPrice: String = ""
    
    var groupMembers: [String] {
        store.getGroup(id: groupName)?.members ?? []
    }
    

    private var subtotal: Double {
        items.reduce(0) { $0 + $1.1 }
    }
    
    private var total: Double {
        subtotal + tax + tip
    }
    
    var body: some View {
        ZStack {
            FluidBackground()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .home
                        }
                    }) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 60)
                
                HStack {
                    TextField("Receipt Title", text: $title)
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundColor(.white)
                    
                    Image(systemName: "pencil")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 10)
                .padding(.bottom, 20)
                
                // List of items
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(items.indices, id: \.self) { index in
                            receiptItemRow(index: index)
                        }
                        
                        Divider().background(Color.white.opacity(0.3)).padding(.vertical, 10)
                        
                        // Tax and Tip (Editable but not assignable)
                        nonAssignableRow(title: "Tax", value: tax, target: .tax)
                        nonAssignableRow(title: "Tip", value: tip, target: .tip)
                        
                        // Summary Card
                        VStack(spacing: 10) {
                            HStack {
                                Text("Subtotal")
                                    .foregroundColor(.white.opacity(0.7))
                                Spacer()
                                Text(String(format: "$%.2f", subtotal))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            HStack {
                                Text("Total")
                                    .font(.system(.title3, design: .serif))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Spacer()
                                Text(String(format: "$%.2f", total))
                                    .font(.system(.title3, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignSystem.accentMustard)
                            }
                        }
                        .padding(24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 120)
                }
            }
            

            // Floating Action Button to proceed
            VStack {
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        appState = .balances(group: groupName, title: title, items: items, assignments: assignments, tax: tax, tip: tip)
                    }
                }) {
                    Text("Calculate Balances")
                }
                .primaryButton()
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
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
                        .font(.system(.title3, design: .serif))
                        .foregroundColor(.white)
                    
                    if case .item(_) = target {
                        TextField("Item Name", text: $editName)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                    }
                    
                    HStack {
                        Text("$").foregroundColor(.white.opacity(0.7))
                        TextField("Amount", text: $editPrice)
                            .keyboardType(.decimalPad)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    
                    HStack(spacing: 15) {
                        Button("Cancel") {
                            withAnimation { editingTarget = nil }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        
                        Button("Save") {
                            saveEdit()
                            withAnimation { editingTarget = nil }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.accentSage)
                        .cornerRadius(12)
                        .foregroundColor(.white)
                    }
                }
                .padding(30)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                .padding(.horizontal, 40)
                .transition(.scale.combined(with: .opacity))
            }
        }

    }
    
    private func receiptItemRow(index: Int) -> some View {
        let assignedMembers = assignments[index] ?? []
        let isAssigned = !assignedMembers.isEmpty
        
        return VStack(spacing: 16) {
            HStack {
                Text(items[index].0)
                    .font(.system(.title3, design: .serif))
                    .foregroundColor(.white)
                Spacer()
                
                HStack(spacing: 8) {
                    Text(String(format: "$%.2f", items[index].1))
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Button(action: {
                        openEditModal(for: .item(index))
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.system(size: 20))
                    }
                }
            }
            
            // Inline Member Selectors
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(Array(groupMembers.enumerated()), id: \.element) { i, member in
                        let isSelected = assignedMembers.contains(member)
                        let color = memberColors[i % memberColors.count]
                        
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                if assignments[index] == nil {
                                    assignments[index] = []
                                }
                                
                                if isSelected {
                                    assignments[index]?.remove(member)
                                } else {
                                    assignments[index]?.insert(member)
                                }
                            }
                        }) {
                            Text(String(member.prefix(1)))
                                .font(.system(size: 18, weight: isSelected ? .bold : .medium, design: .serif))
                                .foregroundColor(isSelected ? .white : color)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(isSelected ? color : color.opacity(0.15))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? .clear : color.opacity(0.3), lineWidth: 1)
                                )
                                .scaleEffect(isSelected ? 1.1 : 1.0)
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isAssigned ? Color.white.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 15, y: 8)
    }

    private func nonAssignableRow(title: String, value: Double, target: EditTarget) -> some View {
        HStack {
            Text(title)
                .font(.system(.title3, design: .serif))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 8) {
                Text(String(format: "$%.2f", value))
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                
                Button(action: {
                    openEditModal(for: target)
                }) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 20))
                }
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
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
            editName = items[index].0
            editPrice = String(format: "%.2f", items[index].1)
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
            items[index] = (editName, amount)
        case .tax:
            tax = amount
        case .tip:
            tip = amount
        case .none: break
        }
    }
}