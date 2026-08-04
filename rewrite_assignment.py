import re

with open("iOS/Fidelity/Sources/Views/BespokeAssignmentView.swift", "r") as f:
    content = f.read()

# Add edit state variables
state_vars = """    // State to track which members are assigned to which item index (allows multiple)
    @State private var assignments: [Int: Set<String>] = [:]
    
    // Editing State
    enum EditTarget: Equatable { case item(Int), tax, tip }
    @State private var editingTarget: EditTarget? = nil
    @State private var editName: String = ""
    @State private var editPrice: String = ""
"""
content = re.sub(r'    // State to track which members are assigned to which item index \(allows multiple\)\n    @State private var assignments: \[Int: Set<String>\] = \[:\]\n', state_vars, content)

# Add edit modal overlay at the end of ZStack
edit_modal = """
            // Floating Action Button to proceed
            VStack {
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        appState = .balances(group: groupName, items: items, assignments: assignments, tax: tax, tip: tip)
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
"""
content = re.sub(r'            // Floating Action Button to proceed\n            VStack \{\n                Spacer\(\)\n                Button\(action: \{\n                    withAnimation\(\.spring\(response: 0.6, dampingFraction: 0.8\)\) \{\n                        appState = \.balances\(group: groupName, items: items, assignments: assignments, tax: tax, tip: tip\)\n                    \}\n                \}\) \{\n                    Text\("Calculate Balances"\)\n                \}\n                \.primaryButton\(\)\n                \.padding\(\.horizontal, 40\)\n                \.padding\(\.bottom, 40\)\n            \}\n        \}', edit_modal, content)

# Change receiptItemRow to use edit buttons
receipt_row_old = """    private func receiptItemRow(index: Int) -> some View {
        let assignedMembers = assignments[index] ?? []
        let isAssigned = !assignedMembers.isEmpty
        
        return VStack(spacing: 16) {
            HStack {
                TextField("Item", text: $items[index].0)
                    .font(.system(.title3, design: .serif))
                    .foregroundColor(.white)
                Spacer()
                
                HStack(spacing: 2) {
                    Text("$").foregroundColor(.white.opacity(0.8))
                    TextField("0.00", value: $items[index].1, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 60)
                }
            }"""
receipt_row_new = """    private func receiptItemRow(index: Int) -> some View {
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
            }"""
content = content.replace(receipt_row_old, receipt_row_new)

# Change nonAssignableRow to use edit buttons
non_assignable_row_old = """    private func nonAssignableRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(.system(.title3, design: .serif))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 2) {
                Text("$").foregroundColor(.white.opacity(0.8))
                TextField("0.00", value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 60)
            }
        }"""
non_assignable_row_new = """    private func nonAssignableRow(title: String, value: Double, target: EditTarget) -> some View {
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
        }"""
content = content.replace(non_assignable_row_old, non_assignable_row_new)

# Also update the nonAssignableRow calls
content = content.replace('nonAssignableRow(title: "Tax", value: $tax)', 'nonAssignableRow(title: "Tax", value: tax, target: .tax)')
content = content.replace('nonAssignableRow(title: "Tip", value: $tip)', 'nonAssignableRow(title: "Tip", value: tip, target: .tip)')

# Add helper methods for edit modal
helper_methods = """
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
}"""
content = re.sub(r'\}\s*$', helper_methods, content)

with open("iOS/Fidelity/Sources/Views/BespokeAssignmentView.swift", "w") as f:
    f.write(content)
