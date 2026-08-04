import SwiftUI

enum AppState: Equatable {
    case home
    case groupDetail(group: String)
    case capture(group: String)
    case assignment(group: String, title: String, items: [(String, Double)], tax: Double, tip: Double)
    case balances(group: String, title: String, items: [(String, Double)], assignments: [Int: Set<String>], tax: Double, tip: Double)
    
    // Custom equality to satisfy Equatable for complex associated values
    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.groupDetail(let a), .groupDetail(let b)): return a == b
        case (.capture(let a), .capture(let b)): return a == b
        case (.assignment(let a, let t1, _, _, _), .assignment(let b, let t2, _, _, _)): return a == b && t1 == t2
        case (.balances(let g1, let t1, _, _, _, _), .balances(let g2, let t2, _, _, _, _)): return g1 == g2 && t1 == t2
        default: return false
        }
    }
}

struct RootView: View {
    @State private var appState: AppState = .home
    @StateObject private var store = AppStore()
    @Namespace private var namespace
    
    var body: some View {
        ZStack {
            FluidBackground()
                .ignoresSafeArea()
            
            switch appState {
            case .home:
                BespokeHomeView(appState: $appState, namespace: namespace)
            case .groupDetail(let group):
                BespokeGroupDetailView(groupName: group, appState: $appState, namespace: namespace)
            case .capture(let group):
                BespokeCaptureView(groupName: group, appState: $appState, namespace: namespace)
            case .assignment(let group, let title, let items, let tax, let tip):
                BespokeAssignmentView(groupName: group, appState: $appState, namespace: namespace, initialTitle: title, initialItems: items, initialTax: tax, initialTip: tip)
            case .balances(let group, let title, let items, let assignments, let tax, let tip):
                BespokeBalancesView(groupName: group, title: title, items: items, assignments: assignments, taxAmount: tax, tipAmount: tip, appState: $appState, namespace: namespace)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: appState)
        .environmentObject(store)
    }
}

#Preview {
    RootView()
}
