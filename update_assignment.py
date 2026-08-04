import re

with open("iOS/Fidelity/Sources/Views/BespokeAssignmentView.swift", "r") as f:
    content = f.read()

# Add initialTitle and title state
init_title = """    let groupName: String
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
    @State private var tip: Double"""
content = re.sub(r'    let groupName: String\n    @Binding var appState: AppState\n    var namespace: Namespace\.ID\n    \n    let initialItems: \[\(String, Double\)\]\n    let initialTax: Double\n    let initialTip: Double\n    \n    @EnvironmentObject var store: AppStore\n    \n    @State private var items: \[\(String, Double\)\]\n    @State private var tax: Double\n    @State private var tip: Double', init_title, content)

# Init title in init()
init_func = """    init(groupName: String, appState: Binding<AppState>, namespace: Namespace.ID, initialTitle: String, initialItems: [(String, Double)], initialTax: Double, initialTip: Double) {
        self.groupName = groupName
        self._appState = appState
        self.namespace = namespace
        self.initialTitle = initialTitle
        self.initialItems = initialItems
        self.initialTax = initialTax
        self.initialTip = initialTip
        
        self._title = State(initialValue: initialTitle)
        self._items = State(initialValue: initialItems)"""
content = re.sub(r'    init\(groupName: String, appState: Binding<AppState>, namespace: Namespace\.ID, initialItems: \[\(String, Double\)\], initialTax: Double, initialTip: Double\) \{\n        self\.groupName = groupName\n        self\._appState = appState\n        self\.namespace = namespace\n        self\.initialItems = initialItems\n        self\.initialTax = initialTax\n        self\.initialTip = initialTip\n        \n        self\._items = State\(initialValue: initialItems\)', init_func, content)

# Add Title editing UI
title_ui = """                // Title Editor
                HStack {
                    TextField("Receipt Title", text: $title)
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                    
                    Image(systemName: "pencil")
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 30)
                .padding(.top, 40)
                
                ScrollView(showsIndicators: false) {"""
content = re.sub(r'                HStack \{\n                    Text\("Assign Items"\)\n                        \.font\(\.system\(size: 40, weight: \.regular, design: \.serif\)\)\n                        \.foregroundColor\(\.white\)\n                    Spacer\(\)\n                \}\n                \.padding\(\.horizontal, 30\)\n                \.padding\(\.top, 40\)\n                \n                ScrollView\(showsIndicators: false\) \{', title_ui, content)

# Pass title to appState
app_state = """                Button(action: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        appState = .balances(group: groupName, title: title, items: items, assignments: assignments, tax: tax, tip: tip)
                    }
                })"""
content = re.sub(r'                Button\(action: \{\n                    withAnimation\(\.spring\(response: 0\.6, dampingFraction: 0\.8\)\) \{\n                        appState = \.balances\(group: groupName, items: items, assignments: assignments, tax: tax, tip: tip\)\n                    \}\n                \}\)', app_state, content)


with open("iOS/Fidelity/Sources/Views/BespokeAssignmentView.swift", "w") as f:
    f.write(content)
