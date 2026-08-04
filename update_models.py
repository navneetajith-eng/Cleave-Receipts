import re

with open("iOS/Fidelity/Sources/Models/FidelityModels.swift", "r") as f:
    content = f.read()

# Add objectWillChange.send() and update ReceiptSplit
save_split = """    func saveSplit(to groupID: String, split: ReceiptSplit) {
        if let index = groups.firstIndex(where: { $0.id == groupID }) {
            objectWillChange.send()
            groups[index].history.append(split)
        }
    }"""
content = re.sub(r'    func saveSplit\(to groupID: String, split: ReceiptSplit\) \{\n        if let index = groups\.firstIndex\(where: \{ \$0\.id == groupID \}\) \{\n            groups\[index\]\.history\.append\(split\)\n        \}\n    \}', save_split, content)

receipt_split = """struct ReceiptSplit: Identifiable {
    let id = UUID()
    let date = Date()
    let items: [(String, Double)]
    let tax: Double
    let tip: Double
    let assignments: [Int: Set<String>]
    var rating: Int? = nil
    var memoryPhotos: [Data]? = nil
}"""
content = re.sub(r'struct ReceiptSplit: Identifiable \{\n    let id = UUID\(\)\n    let date = Date\(\)\n    let items: \[\(String, Double\)\]\n    let tax: Double\n    let tip: Double\n    let assignments: \[Int: Set<String>\]\n\}', receipt_split, content)

with open("iOS/Fidelity/Sources/Models/FidelityModels.swift", "w") as f:
    f.write(content)
