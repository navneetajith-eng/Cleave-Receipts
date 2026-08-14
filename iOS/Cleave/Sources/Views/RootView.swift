import SwiftUI

enum AppState: Equatable {
    case home
    case groupDetail(group: UUID)
    case capture(group: UUID)
    case receiptReview(receipt: RemoteReceipt, group: UUID)
    case assignment(receiptId: String, group: UUID, title: String, items: [ReceiptItem], assignments: [String: Set<String>], tax: Double, tip: Double, discount: Double, currency: Currency, viewerIsAdmin: Bool, adminOverrideMode: Bool)
    case balances(receiptId: String, group: UUID, title: String, items: [ReceiptItem], assignments: [String: Set<String>], tax: Double, tip: Double, discount: Double, currency: Currency, viewerIsAdmin: Bool, initialReview: ReceiptReview?)

    // Custom equality to satisfy Equatable for complex associated values
    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.groupDetail(let a), .groupDetail(let b)): return a == b
        case (.capture(let a), .capture(let b)): return a == b
        case (.receiptReview(let a, let g1), .receiptReview(let b, let g2)): return a.id == b.id && g1 == g2
        case (.assignment(let r1, let a, let t1, _, _, _, _, _, _, _, _), .assignment(let r2, let b, let t2, _, _, _, _, _, _, _, _)): return r1 == r2 && a == b && t1 == t2
        case (.balances(let r1, let g1, let t1, _, _, _, _, _, _, _, _), .balances(let r2, let g2, let t2, _, _, _, _, _, _, _, _)): return r1 == r2 && g1 == g2 && t1 == t2
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
        isDemoMode: Bool = false,
        isReplayingOnboarding: Bool = false
    ) -> LaunchDestination {
        if isReplayingOnboarding {
            if !isDemoMode && isSupabaseConfigured && !hasCheckedSession {
                return .sessionLoading
            }
            return .onboarding
        }
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
    @AppStorage("onboardingReplayRequested") private var onboardingReplayRequested = false
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
            isDemoMode: isDemoMode,
            isReplayingOnboarding: onboardingReplayRequested
        )
    }

    var body: some View {
        Group {
            switch launchDestination {
            case .onboarding:
                OnboardingView(isReplay: onboardingReplayRequested, onComplete: finishOnboarding)
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
                    case .receiptReview(let receipt, let group):
                        ReceiptReviewView(receipt: receipt, groupId: group, appState: $appState)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                            .zIndex(10)
                    case .assignment(let receiptId, let group, let title, let items, let assignments, let tax, let tip, let discount, let currency, let viewerIsAdmin, let adminOverrideMode):
                        BespokeAssignmentView(receiptId: receiptId, groupId: group, appState: $appState, namespace: namespace, initialTitle: title, initialItems: items, initialAssignments: assignments, initialTax: tax, initialTip: tip, initialDiscount: discount, currency: currency, viewerIsAdmin: viewerIsAdmin, adminOverrideMode: adminOverrideMode)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .zIndex(10)
                    case .balances(let receiptId, let group, let title, let items, let assignments, let tax, let tip, let discount, let currency, let viewerIsAdmin, let initialReview):
                        BespokeBalancesView(receiptId: receiptId, groupId: group, title: title, items: items, assignments: assignments, tax: tax, tip: tip, discount: discount, currency: currency, viewerIsAdmin: viewerIsAdmin, initialReview: initialReview, appState: $appState, namespace: namespace)
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

    private func finishOnboarding() {
        let wasReplay = onboardingReplayRequested
        onboardingVersion = OnboardingVersion.current
        onboardingReplayRequested = false
        guard !wasReplay else { return }
        guard session.currentUser != nil else { return }
        Task {
            if let ageBand = AgePreferences.ageBand {
                _ = try? await CleaveAPI.shared.updateProfile(ageBand: ageBand)
            }
            await syncPaymentPreferencesIfReady()
        }
    }

    private func syncPaymentPreferencesIfReady() async {
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
                upiID: PaymentPreferences.upiID,
                aaniID: PaymentPreferences.aaniID
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
