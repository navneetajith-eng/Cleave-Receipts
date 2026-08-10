import SwiftUI

enum AppState: Equatable {
    case home
    case groupDetail(group: UUID)
    case capture(group: UUID)
    case assignment(receiptId: String, group: UUID, title: String, items: [ReceiptItem], assignments: [String: Set<String>], tax: Double, tip: Double, discount: Double)
    case balances(receiptId: String, group: UUID, title: String, items: [ReceiptItem], assignments: [String: Set<String>], tax: Double, tip: Double, discount: Double)

    // Custom equality to satisfy Equatable for complex associated values
    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.groupDetail(let a), .groupDetail(let b)): return a == b
        case (.capture(let a), .capture(let b)): return a == b
        case (.assignment(let r1, let a, let t1, _, _, _, _, _), .assignment(let r2, let b, let t2, _, _, _, _, _)): return r1 == r2 && a == b && t1 == t2
        case (.balances(let r1, let g1, let t1, _, _, _, _, _), .balances(let r2, let g2, let t2, _, _, _, _, _)): return r1 == r2 && g1 == g2 && t1 == t2
        default: return false
        }
    }
}

enum LaunchDestination: Equatable {
    case onboarding
    case sessionLoading
    case configurationRequired
    case authentication
    case app
}

enum LaunchFlow {
    static func destination(
        hasSeenOnboarding: Bool,
        hasCheckedSession: Bool,
        hasUser: Bool,
        isSupabaseConfigured: Bool
    ) -> LaunchDestination {
        if !hasSeenOnboarding { return .onboarding }
        if !isSupabaseConfigured { return .configurationRequired }
        if !hasCheckedSession { return .sessionLoading }
        return hasUser ? .app : .authentication
    }
}

struct RootView: View {
    @State private var appState: AppState = .home
    @StateObject private var store = AppStore()
    @ObservedObject private var session = SupabaseManager.shared
    @Namespace private var namespace

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    private var launchDestination: LaunchDestination {
        LaunchFlow.destination(
            hasSeenOnboarding: hasSeenOnboarding,
            hasCheckedSession: session.hasCheckedSession,
            hasUser: session.currentUser != nil,
            isSupabaseConfigured: AppConfiguration.isSupabaseConfigured
        )
    }

    var body: some View {
        Group {
            switch launchDestination {
            case .onboarding:
                OnboardingView {
                    hasSeenOnboarding = true
                }
            case .sessionLoading:
                ZStack {
                    FluidBackground().ignoresSafeArea()
                    ProgressView("Loading Cleave…")
                        .tint(DesignSystem.accentNavy)
                }
            case .configurationRequired:
                SupabaseConfigurationRequiredView()
            case .authentication:
                AuthView(allowsDismiss: false)
            case .app:
                ZStack {
                    FluidBackground().ignoresSafeArea()
                    BespokeHomeView(appState: $appState, namespace: namespace)

                    switch appState {
                    case .home, .groupDetail:
                        EmptyView()
                    case .capture(let group):
                        BespokeCaptureView(groupId: group, appState: $appState, namespace: namespace)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .zIndex(10)
                    case .assignment(let receiptId, let group, let title, let items, let assignments, let tax, let tip, let discount):
                        BespokeAssignmentView(receiptId: receiptId, groupId: group, appState: $appState, namespace: namespace, initialTitle: title, initialItems: items, initialAssignments: assignments, initialTax: tax, initialTip: tip, initialDiscount: discount)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .zIndex(10)
                    case .balances(let receiptId, let group, let title, let items, let assignments, let tax, let tip, let discount):
                        BespokeBalancesView(receiptId: receiptId, groupId: group, title: title, items: items, assignments: assignments, tax: tax, tip: tip, discount: discount, appState: $appState, namespace: namespace)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .zIndex(10)
                    }
                }
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: appState)
        .environmentObject(store)
        .task {
            await session.checkSession()
            if session.currentUser != nil {
                await store.refreshGroups()
            }
        }
        .onChange(of: session.currentUser?.id) { _, userID in
            appState = .home
            if userID == nil {
                store.clearForSignOut()
            } else {
                Task {
                    await store.refreshGroups()
                }
            }
        }
    }
}

#Preview {
    RootView()
}
