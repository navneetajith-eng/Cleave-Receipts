import SwiftUI

struct BespokeHomeView: View {
    @Binding var appState: AppState
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore

    @State private var showingNewGroupSheet = false

    @State private var showingRenameAlert = false
    @State private var groupToRename: UUID? = nil
    @State private var renameText = ""

    @State private var showingLeaveAlert = false
    @State private var groupToLeave: UUID? = nil

    // Auth State
    @ObservedObject private var supabaseManager = SupabaseManager.shared
    @State private var showingSettingsSheet = false
    @State private var showingProfileSheet = false
    @State private var showingInboxSheet = false
    @State private var showingDemoControls = false
    @State private var inboxItems: [InboxItem] = []

    // Some vibrant colors to cycle through for groups
    let cardColors = [DesignSystem.cardNavy, DesignSystem.cardTeal, DesignSystem.cardOrange, DesignSystem.cardPeach]

    var body: some View {
        ZStack {
            FluidBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {

                headerView

                if DemoMode.isEnabled {
                    Label("DEMO DATA · LOCAL ONLY", systemImage: "flask.fill")
                        .font(.custom("AvenirNext-Heavy", size: 11))
                        .tracking(1.2)
                        .foregroundColor(DesignSystem.accentOrange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DesignSystem.accentOrange.opacity(0.12))
                        .clipShape(Capsule())
                        .padding(.horizontal, 20)
                }

                Text("Select a group to split receipts.")
                    .font(DesignSystem.bodyFont(14))
                    .foregroundColor(Color.black.opacity(0.5))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                if store.groups.isEmpty {
                    Spacer()
                    EmptyStateView(
                        iconName: "person.3.sequence.fill",
                        title: "No Groups Yet",
                        message: "Tap the + button below to create your first group and start splitting receipts."
                    )
                    Spacer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            // Left Column
                            VStack(spacing: 16) {
                                ForEach(Array(store.groups.enumerated()).filter { $0.offset % 2 == 0 }, id: \.element.id) { index, group in
                                    let color = cardColors[index % cardColors.count]

                                    Button(action: {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                                            appState = .groupDetail(group: group.id)
                                        }
                                    }) {
                                        GroupCard(
                                            title: group.name,
                                            members: group.members.count,
                                            color: color,
                                            namespace: namespace,
                                            id: group.id,
                                            isCollaborative: group.isCollaborative
                                        )
                                    }
                                    .buttonStyle(PressScaleButtonStyle())
                                    .contextMenu {
                                        if !group.isCollaborative || group.createdBy == supabaseManager.currentUser?.id {
                                            Button {
                                                groupToRename = group.id
                                                renameText = group.name
                                                showingRenameAlert = true
                                            } label: { Label("Rename", systemImage: "pencil") }
                                        }

                                        Button(role: .destructive) {
                                            groupToLeave = group.id
                                            showingLeaveAlert = true
                                        } label: { Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right") }
                                    }
                                }
                            }

                            // Right Column (Staggered offset)
                            VStack(spacing: 16) {
                                ForEach(Array(store.groups.enumerated()).filter { $0.offset % 2 != 0 }, id: \.element.id) { index, group in
                                    let color = cardColors[index % cardColors.count]

                                    Button(action: {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                                            appState = .groupDetail(group: group.id)
                                        }
                                    }) {
                                        GroupCard(
                                            title: group.name,
                                            members: group.members.count,
                                            color: color,
                                            namespace: namespace,
                                            id: group.id,
                                            isCollaborative: group.isCollaborative
                                        )
                                    }
                                    .buttonStyle(PressScaleButtonStyle())
                                    .contextMenu {
                                        if !group.isCollaborative || group.createdBy == supabaseManager.currentUser?.id {
                                            Button {
                                                groupToRename = group.id
                                                renameText = group.name
                                                showingRenameAlert = true
                                            } label: { Label("Rename", systemImage: "pencil") }
                                        }

                                        Button(role: .destructive) {
                                            groupToLeave = group.id
                                            showingLeaveAlert = true
                                        } label: { Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right") }
                                    }
                                }
                            }
                            .padding(.top, 40) // The primary stagger offset for the entire column
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 150)
                    }
                }

                Spacer()
            }
            .overlay(alignment: .bottom) {
                bottomToolbar
            }

            // Old notification overlay removed

            // Expanded Card Overlay
            if case .groupDetail(let groupId) = appState {
                if let groupIndex = store.groups.firstIndex(where: { $0.id == groupId }) {
                    let color = cardColors[groupIndex % cardColors.count]

                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                                appState = .home
                            }
                        }

                    BespokeGroupDetailView(
                        groupId: groupId,
                        color: color,
                        appState: $appState,
                        namespace: namespace
                    )
                    .zIndex(2) // ensure it renders above everything
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $showingNewGroupSheet) {
            NewGroupSheetView(isPresented: $showingNewGroupSheet)
                .presentationDragIndicator(.hidden)
                .presentationDetents([.fraction(0.72), .large])
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsSheetView(isPresented: $showingSettingsSheet)
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingProfileSheet) {
            ProfileSheetView(isPresented: $showingProfileSheet)
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingDemoControls) {
            DemoControlSheet(isPresented: $showingDemoControls)
                .presentationDragIndicator(.visible)
                .presentationDetents([.height(470)])
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $showingInboxSheet, onDismiss: {
            Task { await refreshInbox() }
        }) {
            InboxSheetView(
                isPresented: $showingInboxSheet,
                appState: $appState,
                items: $inboxItems
            )
            .presentationDragIndicator(.visible)
            .presentationDetents([.large])
        }
        .alert("Rename Group", isPresented: $showingRenameAlert) {
            TextField("New Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let id = groupToRename, !renameText.isEmpty {
                    if let group = store.getGroup(id: id), !group.isCollaborative {
                        store.renameGroup(id: id, newName: renameText)
                        return
                    }
                    Task {
                        do {
                            let updated = try await CleaveAPI.shared.renameGroup(id: id, name: renameText)
                            await MainActor.run { store.replace(with: updated) }
                        } catch {
                            ErrorManager.shared.showError(error.localizedDescription)
                        }
                    }
                }
            }
        }
        .alert("Leave Group?", isPresented: $showingLeaveAlert, presenting: groupToLeave) { id in
            Button("Leave", role: .destructive) {
                if let group = store.getGroup(id: id), !group.isCollaborative {
                    withAnimation { store.deleteGroup(id: id) }
                    return
                }
                Task {
                    do {
                        try await CleaveAPI.shared.leaveGroup(id: id)
                        await MainActor.run {
                            withAnimation { store.deleteGroup(id: id) }
                        }
                    } catch {
                        ErrorManager.shared.showError(error.localizedDescription)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The group and its receipts stay available to everyone else. You will lose access unless another member adds you again.")
        }
        .task { await refreshInbox() }
    }

    private var headerView: some View {
        HStack {
            HStack(spacing: 10) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text("CLEAVE")
                    .font(.custom("AvenirNext-Heavy", size: 24))
                    .tracking(4.5)
                    .foregroundColor(Color.black.opacity(0.85))
            }

            Spacer()

            // Top right icons
            HStack(spacing: 20) {
                // Profile Icon
                Button(action: {
                    HapticsManager.shared.playImpact(style: .light)
                    if DemoMode.isEnabled {
                        showingDemoControls = true
                    } else {
                        showingProfileSheet = true
                    }
                }) {
                    if DemoMode.isEnabled {
                        Image(systemName: "flask.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(DesignSystem.accentOrange)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
                    } else if let user = supabaseManager.currentUser {
                        ProfileAvatarView(
                            profileID: user.id,
                            fallbackName: user.email ?? "User",
                            size: 44
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.white)
                            .font(.system(size: 20))
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Circle())
                    }
                }
                .accessibilityLabel(DemoMode.isEnabled ? "Open Demo Lab" : "Profile and friends")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    private var bottomToolbar: some View {
        HStack {
            toolbarButton(systemName: "tray.fill", label: "Inbox", action: { showingInboxSheet = true })
                .overlay(alignment: .topTrailing) {
                    let unreadCount = inboxItems.filter { !$0.isRead }.count
                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(DesignSystem.labelFont(8))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(DesignSystem.accentOrange, in: Capsule())
                            .offset(x: 4, y: -3)
                    }
                }

            Spacer()
            toolbarButton(systemName: "plus", label: "New group", prominent: true, action: { showingNewGroupSheet = true })
            Spacer()
            toolbarButton(systemName: "gearshape.fill", label: "Settings", action: { showingSettingsSheet = true })
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.52), lineWidth: 0.7))
        .shadow(color: DesignSystem.accentNavy.opacity(0.12), radius: 16, y: 6)
        .padding(.horizontal, 18)
        .padding(.bottom, 34)
    }

    private func toolbarButton(
        systemName: String,
        label: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 22 : 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: prominent ? 52 : 46, height: prominent ? 52 : 46)
                .background(prominent ? DesignSystem.accentOrange : Color.black, in: Circle())
                .shadow(color: DesignSystem.accentNavy.opacity(prominent ? 0.18 : 0.1), radius: 8, y: 3)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }

    @MainActor
    private func refreshInbox() async {
        guard !DemoMode.isEnabled else {
            inboxItems = []
            return
        }
        do {
            inboxItems = try await CleaveAPI.shared.fetchInbox()
        } catch {
            // Keep the home screen usable while offline; Inbox can retry when opened.
        }
    }

    // Removed greeting message as we are using the App Name now

    // Custom Speech Bubble Dropdown
    // notificationDropdown removed
}

private struct DemoControlSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: AppStore
    @AppStorage(DemoMode.defaultsKey) private var demoModeEnabled = false

    @State private var showingResetConfirmation = false
    @State private var showingExitConfirmation = false

    private var receiptCount: Int {
        store.groups.reduce(0) { count, group in
            count + store.receipts(for: group.id).count
        }
    }

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            CleaveReceiptWatermark(color: DesignSystem.accentOrange)
                .rotationEffect(.degrees(10))
                .position(x: 380, y: 80)
                .opacity(0.42)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(DesignSystem.accentOrange.opacity(0.14))
                            .frame(width: 68, height: 68)
                        Circle()
                            .stroke(DesignSystem.accentOrange.opacity(0.22), lineWidth: 1)
                            .frame(width: 78, height: 78)
                        Image(systemName: "flask.fill")
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(DesignSystem.accentOrange)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("DEMO LAB")
                            .font(DesignSystem.labelFont(10))
                            .tracking(1.8)
                            .foregroundStyle(DesignSystem.accentOrange)
                        Text("Try everything")
                            .font(DesignSystem.displayFont(27))
                            .foregroundStyle(DesignSystem.ink)
                        Text("Local data. No real payments.")
                            .font(DesignSystem.bodyFont(14))
                            .foregroundStyle(DesignSystem.inkMuted)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    demoStat(value: "\(store.groups.count)", label: "GROUPS", color: DesignSystem.accentTeal)
                    demoStat(value: "\(receiptCount)", label: "RECEIPTS", color: DesignSystem.accentOrange)
                    demoStat(value: "FREE", label: "TO EXPLORE", color: DesignSystem.accentNavy)
                }

                Button {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset demo data", systemImage: "arrow.counterclockwise")
                        .font(DesignSystem.titleFont(15))
                        .foregroundStyle(DesignSystem.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(DesignSystem.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignSystem.hairline, lineWidth: 1))
                }
                .buttonStyle(PressScaleButtonStyle())

                Button {
                    showingExitConfirmation = true
                } label: {
                    Text("Exit demo")
                        .font(DesignSystem.titleFont(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(DesignSystem.accentNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .preferredColorScheme(.light)
        .alert("Reset the demo?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset") {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    store.loadDemoData()
                }
                HapticsManager.shared.playNotification(type: .success)
                isPresented = false
            }
        } message: {
            Text("This replaces your demo changes with Cleave's original sample groups and receipts.")
        }
        .alert("Exit demo mode?", isPresented: $showingExitConfirmation) {
            Button("Keep exploring", role: .cancel) { }
            Button("Exit Demo", role: .destructive) {
                store.clearForSignOut()
                demoModeEnabled = false
                isPresented = false
            }
        } message: {
            Text("You’ll return to sign in. Demo data never affects a real account.")
        }
    }

    private func demoStat(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(DesignSystem.displayFont(value.count > 4 ? 15 : 22))
                .foregroundStyle(DesignSystem.ink)
            Text(label)
                .font(DesignSystem.labelFont(8))
                .tracking(0.8)
                .foregroundStyle(DesignSystem.inkMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ReceiptCardShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let cornerRadius: CGFloat = 16

        // Start top left
        path.move(to: CGPoint(x: 0, y: cornerRadius))
        path.addArc(center: CGPoint(x: cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: 0))
        path.addArc(center: CGPoint(x: rect.width - cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)

        let toothHeight: CGFloat = 8
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - toothHeight))

        // Jagged bottom edge
        let numberOfTeeth = Int(rect.width / 15)
        let toothWidth = rect.width / CGFloat(numberOfTeeth)

        for i in 0..<numberOfTeeth {
            let startX = rect.width - (CGFloat(i) * toothWidth)
            let midX = startX - (toothWidth / 2)
            let endX = startX - toothWidth

            path.addLine(to: CGPoint(x: midX, y: rect.height))
            path.addLine(to: CGPoint(x: endX, y: rect.height - toothHeight))
        }

        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        path.closeSubpath()
        return path
    }
}

struct GroupCard: View {
    let title: String
    let members: Int
    let color: Color
    let namespace: Namespace.ID
    let id: UUID
    var isCollaborative: Bool = false

    private var isDark: Bool {
        return color == DesignSystem.cardNavy || color == DesignSystem.cardTeal || color == DesignSystem.cardOrange || color == DesignSystem.cardPeach
    }

    private var textColor: Color {
        return isDark ? .white : .black
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECEIPTS")
                        .font(DesignSystem.labelFont(10))
                        .foregroundColor(textColor.opacity(0.6))
                        .kerning(1.5)

                    Text(title)
                        .font(DesignSystem.titleFont(21))
                        .foregroundColor(textColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                }

                Spacer()

                ZStack(alignment: .topTrailing) {
                    Image(systemName: isCollaborative ? "person.2.fill" : "person.fill")
                        .foregroundColor(textColor.opacity(0.5))
                }
                Text("\(members)")
                    .font(DesignSystem.labelFont(13))
                    .foregroundColor(textColor.opacity(0.7))
            }

            Divider()
                .background(textColor.opacity(0.3))
                .padding(.vertical, 8)

            HStack {
                Text("TOTAL ITEMS")
                    .font(DesignSystem.labelFont(10))
                    .foregroundColor(textColor.opacity(0.6))

                Spacer()

                Text("--")
                    .font(DesignSystem.labelFont(13))
                    .foregroundColor(textColor)
            }

            Spacer()
        }
        .padding(24)
        .frame(height: 220)
        .background(color)
        .clipShape(ReceiptCardShape())
        .shadow(color: Color.black.opacity(0.4), radius: 15, y: 10)
        .shadow(color: Color.black.opacity(0.2), radius: 5, y: 3)
        .matchedGeometryEffect(id: "groupBackground-\(id)", in: namespace)
    }
}
