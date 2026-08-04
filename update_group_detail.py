import re

with open("iOS/Fidelity/Sources/Views/BespokeGroupDetailView.swift", "r") as f:
    content = f.read()

# Add history section
history_section = """                            }
                        }
                        .padding(.horizontal, 30)
                    }
                    
                    // History Section
                    if !group.history.isEmpty {
                        Text("Past Receipts")
                            .font(.system(.title3, design: .serif))
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.top, 20)
                            
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 15) {
                                ForEach(group.history) { split in
                                    receiptHistoryCard(split: split)
                                }
                            }
                            .padding(.horizontal, 30)
                            .padding(.bottom, 120)
                        }
                    } else {
                        Spacer()
                    }
                }
"""

content = re.sub(r'                            \}\n                        \}\n                        \.padding\(\.horizontal, 30\)\n                    \}\n                    Spacer\(\)\n                \}', history_section, content)

# Add receiptHistoryCard method
history_card = """
    private func receiptHistoryCard(split: ReceiptSplit) -> some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        let subtotal = split.items.reduce(0) { $0 + $1.1 }
        let total = subtotal + split.tax + split.tip
        
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatter.string(from: split.date))
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(split.items.count) items")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Text(String(format: "$%.2f", total))
                .font(.system(.title3, design: .rounded))
                .foregroundColor(DesignSystem.accentMustard)
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
"""

content = re.sub(r'\}\s*$', history_card, content)

with open("iOS/Fidelity/Sources/Views/BespokeGroupDetailView.swift", "w") as f:
    f.write(content)
