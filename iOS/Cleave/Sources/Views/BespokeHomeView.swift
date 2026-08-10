import SwiftUI

struct BespokeHomeView: View {
    @Binding var appState: AppState
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore

    @State private var showingNewGroupSheet = false
    @State private var isPulsing = false

    @State private var showingRenameAlert = false
    @State private var groupToRename: UUID? = nil
    @State private var renameText = ""

    @State private var showingDeleteAlert = false
    @State private var groupToDelete: UUID? = nil

    // Auth State
    @ObservedObject private var supabaseManager = SupabaseManager.shared
    @State private var showingSettingsSheet = false
    @State private var showingProfileSheet = false
    @State private var showingInboxSheet = false
    @State private var inboxItems: [InboxItem] = []

    // Some vibrant colors to cycle through for groups
    let cardColors = [DesignSystem.cardNavy, DesignSystem.cardTeal, DesignSystem.cardOrange, DesignSystem.cardPeach]

    var body: some View {
        ZStack {
            FluidBackground()

            VStack(alignment: .leading, spacing: 10) {

                headerView

                Text("Select a group to split receipts.")
                    .font(.subheadline)
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
                                        Button {
                                            groupToRename = group.id
                                            renameText = group.name
                                            showingRenameAlert = true
                                        } label: { Label("Rename", systemImage: "pencil") }

                                        Button(role: .destructive) {
                                            groupToDelete = group.id
                                            showingDeleteAlert = true
                                        } label: { Label("Delete", systemImage: "trash") }
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
                                        Button {
                                            groupToRename = group.id
                                            renameText = group.name
                                            showingRenameAlert = true
                                        } label: { Label("Rename", systemImage: "pencil") }

                                        Button(role: .destructive) {
                                            groupToDelete = group.id
                                            showingDeleteAlert = true
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                }
                            }
                            .padding(.top, 40) // The primary stagger offset for the entire column
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 120)
                    }
                }

                Spacer()
            }
            .overlay(
                VStack {
                    Spacer()
                    HStack {
                        Button(action: {
                            showingInboxSheet = true
                        }) {
                            Image(systemName: "tray.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 54, height: 54)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.85))
                                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                                )
                                .overlay(alignment: .topTrailing) {
                                    let unreadCount = inboxItems.filter { !$0.isRead }.count
                                    if unreadCount > 0 {
                                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                                            .font(.system(size: 10, weight: .black, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .frame(minWidth: 20, minHeight: 20)
                                            .background(DesignSystem.accentOrange)
                                            .clipShape(Capsule())
                                            .offset(x: 5, y: -5)
                                    }
                                }
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .accessibilityLabel("Inbox")

                        Spacer()

                        Button(action: {
                            showingNewGroupSheet = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 54, height: 54)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.85))
                                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                                )
                        }
                        .buttonStyle(PressScaleButtonStyle())

                        Spacer()

                        Button(action: {
                            showingSettingsSheet = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 54, height: 54)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.85))
                                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                                )
                        }
                        .buttonStyle(PressScaleButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                }
            )

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
        .sheet(isPresented: $showingNewGroupSheet) {
            NewGroupSheetView(isPresented: $showingNewGroupSheet)
                .presentationDragIndicator(.hidden)
                .presentationDetents([.fraction(0.45), .large])
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
        .alert("Delete Group", isPresented: $showingDeleteAlert, presenting: groupToDelete) { id in
            Button("Delete", role: .destructive) {
                if let group = store.getGroup(id: id), !group.isCollaborative {
                    withAnimation { store.deleteGroup(id: id) }
                    return
                }
                Task {
                    do {
                        try await CleaveAPI.shared.deleteGroup(id: id)
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
            Text("Are you sure you want to delete this group? This action cannot be undone.")
        }
        .task { await refreshInbox() }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CLEAVE")
                    .font(.custom("AvenirNext-Heavy", size: 26))
                    .tracking(6)
                    .foregroundColor(Color.black.opacity(0.85))
            }

            Spacer()

            // Top right icons
            HStack(spacing: 20) {
                // Profile Icon
                Button(action: {
                    HapticsManager.shared.playImpact(style: .light)
                    showingProfileSheet = true
                }) {
                    if let user = supabaseManager.currentUser {
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
                .accessibilityLabel("Profile and friends")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    @MainActor
    private func refreshInbox() async {
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
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(textColor.opacity(0.6))
                        .kerning(1.5)

                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
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
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(textColor.opacity(0.7))
            }

            Divider()
                .background(textColor.opacity(0.3))
                .padding(.vertical, 8)

            HStack {
                Text("TOTAL ITEMS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(textColor.opacity(0.6))

                Spacer()

                Text("--")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
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
