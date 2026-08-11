import SwiftUI

enum AppState: Equatable {
    case home
    case groupDetail(group: UUID)
    case capture(group: UUID)
    case assignment(receiptId: String, group: UUID, title: String, items: [ReceiptItem], assignments: [String: Set<String>], tax: Double, tip: Double, discount: Double, currency: Currency)
    case balances(receiptId: String, group: UUID, title: String, items: [ReceiptItem], assignments: [String: Set<String>], tax: Double, tip: Double, discount: Double, currency: Currency)

    // Custom equality to satisfy Equatable for complex associated values
    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.groupDetail(let a), .groupDetail(let b)): return a == b
        case (.capture(let a), .capture(let b)): return a == b
        case (.assignment(let r1, let a, let t1, _, _, _, _, _, let c1), .assignment(let r2, let b, let t2, _, _, _, _, _, let c2)): return r1 == r2 && a == b && t1 == t2 && c1 == c2
        case (.balances(let r1, let g1, let t1, _, _, _, _, _, let c1), .balances(let r2, let g2, let t2, _, _, _, _, _, let c2)): return r1 == r2 && g1 == g2 && t1 == t2 && c1 == c2
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
        isSupabaseConfigured: Bool,
        isDemoMode: Bool = false
    ) -> LaunchDestination {
        if !hasSeenOnboarding { return .onboarding }
        if isDemoMode { return .app }
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

    @AppStorage("onboardingVersion") private var onboardingVersion = 0
    @AppStorage(DemoMode.defaultsKey) private var demoModeEnabled = false

    private var isDemoMode: Bool {
        #if DEBUG
        return demoModeEnabled
        #else
        return false
        #endif
    }

    private var launchDestination: LaunchDestination {
        LaunchFlow.destination(
            hasSeenOnboarding: onboardingVersion >= OnboardingVersion.current,
            hasCheckedSession: session.hasCheckedSession,
            hasUser: session.currentUser != nil,
            isSupabaseConfigured: AppConfiguration.isSupabaseConfigured,
            isDemoMode: isDemoMode
        )
    }

    var body: some View {
        Group {
            switch launchDestination {
            case .onboarding:
                OnboardingView {
                    onboardingVersion = OnboardingVersion.current
                }
            case .sessionLoading:
                ZStack {
                    FluidBackground().ignoresSafeArea()
                    ProgressView("Loading Cleave…")
                        .tint(DesignSystem.accentNavy)
                }
            case .configurationRequired:
                SupabaseConfigurationRequiredView(onEnterDemo: enterDemoMode)
            case .authentication:
                AuthView(allowsDismiss: false, onEnterDemo: enterDemoMode)
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
                    case .assignment(let receiptId, let group, let title, let items, let assignments, let tax, let tip, let discount, let currency):
                        BespokeAssignmentView(receiptId: receiptId, groupId: group, appState: $appState, namespace: namespace, initialTitle: title, initialItems: items, initialAssignments: assignments, initialTax: tax, initialTip: tip, initialDiscount: discount, currency: currency)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .zIndex(10)
                    case .balances(let receiptId, let group, let title, let items, let assignments, let tax, let tip, let discount, let currency):
                        BespokeBalancesView(receiptId: receiptId, groupId: group, title: title, items: items, assignments: assignments, tax: tax, tip: tip, discount: discount, currency: currency, appState: $appState, namespace: namespace)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .zIndex(10)
                    }
                }
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: appState)
        .environmentObject(store)
        .task {
            if isDemoMode {
                store.loadDemoData()
                return
            }
            await session.checkSession()
            if session.currentUser != nil {
                await syncPaymentPreferencesIfReady()
                await store.refreshGroups()
            }
        }
        .onChange(of: session.currentUser?.id) { _, userID in
            appState = .home
            if userID == nil {
                store.clearForSignOut()
            } else {
                Task {
                    await syncPaymentPreferencesIfReady()
                    await store.refreshGroups()
                }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { session.isPasswordRecovery },
                set: { isPresented in
                    guard !isPresented, session.isPasswordRecovery else { return }
                    Task { await session.cancelPasswordRecovery() }
                }
            )
        ) {
            PasswordUpdateView()
        }
        .onChange(of: demoModeEnabled) { _, enabled in
            appState = .home
            if enabled {
                store.loadDemoData()
            } else {
                store.clearForSignOut()
                Task {
                    await session.checkSession()
                    if session.currentUser != nil {
                        await syncPaymentPreferencesIfReady()
                        await store.refreshGroups()
                    }
                }
            }
        }
    }

    private func enterDemoMode() {
        #if DEBUG
        demoModeEnabled = true
        store.loadDemoData()
        HapticsManager.shared.playNotification(type: .success)
        #endif
    }

    private func syncPaymentPreferencesIfReady() async {
        if let profile = try? await CleaveAPI.shared.fetchCurrentProfile(),
           let regionCode = profile.regionCode,
           let remoteRegion = AppRegion(rawValue: regionCode) {
            PaymentPreferences.hydrate(
                region: remoteRegion,
                venmo: profile.venmoUsername,
                upi: profile.upiId
            )
            return
        }
        let region = RegionManager.shared.currentRegion
        guard PaymentPreferences.needsSync,
              PaymentPreferences.isComplete(
                for: region,
                venmo: PaymentPreferences.venmoUsername,
                upi: PaymentPreferences.upiID
              ) else { return }
        do {
            _ = try await CleaveAPI.shared.updatePaymentDetails(
                region: region,
                venmoUsername: PaymentPreferences.venmoUsername,
                upiID: PaymentPreferences.upiID
            )
            PaymentPreferences.markSynced()
        } catch {
            // Keep the pending flag; Profile remains the manual retry surface.
        }
    }
}

#Preview {
    RootView()
}
