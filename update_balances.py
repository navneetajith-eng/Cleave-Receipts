import re

with open("iOS/Fidelity/Sources/Views/BespokeBalancesView.swift", "r") as f:
    content = f.read()

# Add title state
title_state = """struct BespokeBalancesView: View {
    let groupName: String
    let title: String
"""
content = re.sub(r'struct BespokeBalancesView: View \{\n    let groupName: String\n', title_state, content)


# Update Memories Section
memories_ui = """                // Memories Section
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
                    ScrollView(.horizontal, showsIndicators: false) {"""
content = re.sub(r'                // Memories Section\n                VStack\(spacing: 20\) \{\n                    Text\("Memories"\)\n                        \.font\(\.system\(\.title2, design: \.serif\)\)\n                        \.foregroundColor\(\.white\)\n                    \n                    // Star Rating\n                    HStack\(spacing: 15\) \{\n                        ForEach\(1\.\.\.5, id: \\\.self\) \{ star in\n                            Image\(systemName: star <= rating \? "star\.fill" : "star"\)\n                                \.font\(\.system\(size: 30\)\)\n                                \.foregroundColor\(star <= rating \? DesignSystem\.accentMustard : \.white\.opacity\(0\.3\)\)\n                                \.onTapGesture \{\n                                    withAnimation \{ rating = star \}\n                                \}\n                        \}\n                    \}\n                    \n                    // Photos\n                    ScrollView\(\.horizontal, showsIndicators: false\) \{', memories_ui, content)


# Update Save button split
save_split = """                    let split = ReceiptSplit(
                        title: title,
                        items: items,"""
content = re.sub(r'                    let split = ReceiptSplit\(\n                        items: items,', save_split, content)

with open("iOS/Fidelity/Sources/Views/BespokeBalancesView.swift", "w") as f:
    f.write(content)
