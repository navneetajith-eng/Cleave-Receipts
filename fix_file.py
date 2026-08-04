import re

content = """import SwiftUI
import PhotosUI

struct BreakdownItem: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
}

struct BespokeBalancesView: View {
    let groupName: String
    let title: String
    
    let items: [(String, Double)]
    let assignments: [Int: Set<String>]
    let taxAmount: Double
    let tipAmount: Double
    @Binding var appState: AppState
    var namespace: Namespace.ID
    
    @EnvironmentObject var store: AppStore
    @State private var memberBalances: [(String, Double, [BreakdownItem])] = []
    
    // Memories
    @State private var rating: Int = 0
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedPhotos: [Data] = []
    
    var body: some View {
        ZStack {
            FluidBackground()
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .assignment(group: groupName, title: title, items: items, tax: taxAmount, tip: tipAmount)
                        }
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 60)
                
                Text("Balances")
                    .font(.system(size: 48, weight: .light, design: .serif))
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.top, 10)
                
                Text(String(format: "Including tax ($%.2f) and tip ($%.2f)", taxAmount, tipAmount))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(memberBalances, id: \\.0) { member, total, breakdown in
                            balanceCard(member: member, total: total, breakdown: breakdown)
                        }
                        
                        Divider().background(Color.white.opacity(0.3)).padding(.horizontal, 10)
                        
                        // Memories Section
                        VStack(spacing: 20) {
                            Text("Rate your experience at '\\(title)'!")
                                .font(.system(.title3, design: .serif))
                                .foregroundColor(.white)
                            
                            // Star Rating
                            HStack(spacing: 15) {
                                ForEach(1...5, id: \\.self) { star in
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.system(size: 30))
                                        .foregroundColor(star <= rating ? DesignSystem.accentMustard : .white.opacity(0.3))
                                        .onTapGesture {
                                            withAnimation { rating = star }
                                        }
                                }
                            }
                            
                            Text("Upload your memories at '\\(title)'")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
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
                                        .foregroundColor(.white)
                                        .frame(width: 100, height: 100)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    }
                                    .onChange(of: selectedPhotoItems) { items in
                                        Task {
                                            selectedPhotos = []
                                            for item in items {
                                                if let data = try? await item.loadTransferable(type: Data.self) {
                                                    selectedPhotos.append(data)
                                                }
                                            }
                                        }
                                    }
                                    
                                    ForEach(selectedPhotos.indices, id: \\.self) { index in
                                        if let image = UIImage(data: selectedPhotos[index]) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 150) // Space for button
                    }
                    .padding(.horizontal, 30)
                }
            }

            // Floating Action Button
            VStack {
                Spacer()
                Button(action: {
                    let split = ReceiptSplit(
                        title: title,
                        items: items,
                        tax: taxAmount,
                        tip: tipAmount,
                        assignments: assignments,
                        rating: rating > 0 ? rating : nil,
                        memoryPhotos: selectedPhotos.isEmpty ? nil : selectedPhotos
                    )
                    store.saveSplit(to: groupName, split: split)
                    
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        appState = .groupDetail(group: groupName)
                    }
                }) {
                    Text("Save Receipt")
                }
                .primaryButton()
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            calculateBalances()
        }
    }
    
    private func balanceCard(member: String, total: Double, breakdown: [BreakdownItem]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(member.prefix(1)))
                            .font(.system(size: 20, design: .serif))
                            .foregroundColor(.white)
                    )
                
                Text(member)
                    .font(.system(.title3, design: .serif))
                    .foregroundColor(.white)
                    .padding(.leading, 10)
                
                Spacer()
                
                Text(String(format: "$%.2f", total))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.accentMustard)
            }
            .padding(24)
            
            if !breakdown.isEmpty {
                Divider().background(Color.white.opacity(0.2)).padding(.horizontal, 24)
                
                VStack(spacing: 8) {
                    ForEach(breakdown, id: \\.id) { item in
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text(String(format: "$%.2f", item.amount))
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.1))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 15, y: 8)
    }
    
    private func calculateBalances() {
        var balances: [String: Double] = [:]
        var breakdowns: [String: [BreakdownItem]] = [:]
        var subtotal = 0.0
        
        // 1. Calculate item splits
        for (index, item) in items.enumerated() {
            let assignedMembers = assignments[index] ?? []
            if !assignedMembers.isEmpty {
                let splitAmount = item.1 / Double(assignedMembers.count)
                for member in assignedMembers {
                    balances[member, default: 0.0] += splitAmount
                    breakdowns[member, default: []].append(BreakdownItem(name: item.0, amount: splitAmount))
                }
                subtotal += item.1
            }
        }
        
        // 2. Proportionally distribute tax and tip
        let totalExtra = taxAmount + tipAmount
        if subtotal > 0 {
            for (member, amount) in balances {
                let proportion = amount / subtotal
                
                if taxAmount > 0 {
                    let taxShare = proportion * taxAmount
                    balances[member]! += taxShare
                    breakdowns[member, default: []].append(BreakdownItem(name: "Tax Share", amount: taxShare))
                }
                if tipAmount > 0 {
                    let tipShare = proportion * tipAmount
                    balances[member]! += tipShare
                    breakdowns[member, default: []].append(BreakdownItem(name: "Tip Share", amount: tipShare))
                }
            }
        }
        
        // 3. Convert to sorted array
        memberBalances = balances.map { ($0.key, $0.value, breakdowns[$0.key] ?? []) }.sorted { $0.1 > $1.1 }
    }
}
"""

with open("iOS/Fidelity/Sources/Views/BespokeBalancesView.swift", "w") as f:
    f.write(content)
