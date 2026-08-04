import re

with open("iOS/Fidelity/Sources/Views/BespokeAssignmentView.swift", "r") as f:
    content = f.read()

# Replace the incorrect init signature
new_init = """    init(groupName: String, appState: Binding<AppState>, namespace: Namespace.ID, initialTitle: String, initialItems: [(String, Double)], initialTax: Double, initialTip: Double) {
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
    }"""
content = re.sub(r'    init\(groupName: String, appState: Binding<AppState>, namespace: Namespace\.ID, initialItems: \[\(String, Double\)\], initialTax: Double, initialTip: Double\) \{[\s\S]*?self\._tip = State\(initialValue: initialTip\)\n    \}', new_init, content)

with open("iOS/Fidelity/Sources/Views/BespokeAssignmentView.swift", "w") as f:
    f.write(content)
