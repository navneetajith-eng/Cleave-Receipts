import re

with open("iOS/Fidelity/Sources/Views/BespokeCaptureView.swift", "r") as f:
    content = f.read()

# Add parsedTitle state
parsed_state = """    @State private var parsedItems: [(String, Double)] = []
    @State private var parsedTax: Double = 0
    @State private var parsedTip: Double = 0
    @State private var parsedTitle: String = ""
"""
content = re.sub(r'    @State private var parsedItems: \[\(String, Double\)\] = \[\]\n    @State private var parsedTax: Double = 0\n    @State private var parsedTip: Double = 0\n', parsed_state, content)

# Pass parsedTitle to appState
app_state = """                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .assignment(group: groupName, title: parsedTitle, items: parsedItems, tax: parsedTax, tip: parsedTip)
                        }"""
content = re.sub(r'                        withAnimation\(\.spring\(response: 0\.6, dampingFraction: 0\.8\)\) \{\n                            appState = \.assignment\(group: groupName, items: parsedItems, tax: parsedTax, tip: parsedTip\)\n                        \}', app_state, content)

# Set parsedTitle from response
set_title = """            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    self.parsedTitle = response.vendor_name
                    self.parsedItems = fetchedItems"""
content = re.sub(r'            await MainActor\.run \{\n                withAnimation\(\.spring\(response: 0\.5, dampingFraction: 0\.7\)\) \{\n                    self\.parsedItems = fetchedItems', set_title, content)

with open("iOS/Fidelity/Sources/Views/BespokeCaptureView.swift", "w") as f:
    f.write(content)
