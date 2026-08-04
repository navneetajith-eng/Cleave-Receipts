import re

# 1. Update FidelityModels.swift
with open("iOS/Fidelity/Sources/Models/FidelityModels.swift", "r") as f:
    content = f.read()

content = re.sub(r'    let date = Date\(\)', r'    let date = Date()\n    var title: String', content)

with open("iOS/Fidelity/Sources/Models/FidelityModels.swift", "w") as f:
    f.write(content)

# 2. Update RootView.swift
with open("iOS/Fidelity/Sources/Views/RootView.swift", "r") as f:
    content = f.read()

content = re.sub(r'    case assignment\(group: String, items: \[\(String, Double\)\], tax: Double, tip: Double\)', r'    case assignment(group: String, title: String, items: [(String, Double)], tax: Double, tip: Double)', content)
content = re.sub(r'    case balances\(group: String, items: \[\(String, Double\)\], assignments: \[Int: Set<String>\], tax: Double, tip: Double\)', r'    case balances(group: String, title: String, items: [(String, Double)], assignments: [Int: Set<String>], tax: Double, tip: Double)', content)

content = re.sub(r'        case \(\.assignment\(let a, _, _, _\), \.assignment\(let b, _, _, _\)\): return a == b', r'        case (.assignment(let a, let t1, _, _, _), .assignment(let b, let t2, _, _, _)): return a == b && t1 == t2', content)
content = re.sub(r'        case \(\.balances\(let g1, _, _, _, _\), \.balances\(let g2, _, _, _, _\)\): return g1 == g2', r'        case (.balances(let g1, let t1, _, _, _, _), .balances(let g2, let t2, _, _, _, _)): return g1 == g2 && t1 == t2', content)

content = re.sub(r'            case \.assignment\(let group, let items, let tax, let tip\):', r'            case .assignment(let group, let title, let items, let tax, let tip):', content)
content = re.sub(r'                BespokeAssignmentView\(groupName: group, appState: \$appState, namespace: namespace, initialItems: items, initialTax: tax, initialTip: tip\)', r'                BespokeAssignmentView(groupName: group, appState: $appState, namespace: namespace, initialTitle: title, initialItems: items, initialTax: tax, initialTip: tip)', content)

content = re.sub(r'            case \.balances\(let group, let items, let assignments, let tax, let tip\):', r'            case .balances(let group, let title, let items, let assignments, let tax, let tip):', content)
content = re.sub(r'                BespokeBalancesView\(groupName: group, items: items, assignments: assignments, taxAmount: tax, tipAmount: tip, appState: \$appState, namespace: namespace\)', r'                BespokeBalancesView(groupName: group, title: title, items: items, assignments: assignments, taxAmount: tax, tipAmount: tip, appState: $appState, namespace: namespace)', content)

with open("iOS/Fidelity/Sources/Views/RootView.swift", "w") as f:
    f.write(content)

