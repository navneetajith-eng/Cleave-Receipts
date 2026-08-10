import SwiftUI

struct NewGroupSheetView: View {
    @EnvironmentObject var store: AppStore
    @Binding var isPresented: Bool

    @State private var newGroupName = ""
    @State private var isCollaborative = false
    @State private var sheetDetent: PresentationDetent = .height(560)

    // Search & Members
    @State private var selectedMembers: [Profile] = []
    @State private var localMemberName = ""
    @State private var localMemberNames: [String] = []

    @State private var isCreating = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                Capsule()
                .fill(Color.black.opacity(0.2))
                .frame(width: 40, height: 5)
                .padding(.top, 16)

            Text("Create New Group")
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundColor(.black)

            TextField("Group Name", text: $newGroupName)
                .font(.system(size: 20))
                .foregroundColor(.black)
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal, 30)

            // Custom Toggle for Collaborative Mode
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Collaborative Group")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.black)
                    Text(isCollaborative ? "Invite Cleave users and sync online" : "Use any names and keep this group on this device")
                        .font(.system(size: 12))
                        .foregroundColor(Color.black.opacity(0.6))
                }

                Spacer()

                Toggle("", isOn: $isCollaborative)
                    .labelsHidden()
                    .tint(DesignSystem.accentNavy)
                    .onChange(of: isCollaborative) { _, newValue in
                        withAnimation(.spring()) {
                            sheetDetent = newValue ? .large : .height(560)
                        }
                    }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 10)

            if isCollaborative {
                Divider().padding(.horizontal, 30)
                CollaborativeSearchSheetView(selectedMembers: $selectedMembers, isEmbedded: true)
            } else {
                localMembersSection
            }

            Spacer()

            Button(action: {
                let startedAt = Date()
                let trimmedName = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty && !isCreating else { return }

                if !isCollaborative {
                    addPendingLocalMember()
                    guard let userID = SupabaseManager.shared.currentUser?.id else {
                        ErrorManager.shared.showError("Your local profile is still loading. Please try again.")
                        return
                    }
                    store.createLocalGroup(
                        name: trimmedName,
                        memberNames: localMemberNames,
                        createdBy: userID
                    )
                    ProductMetrics.record(.localGroupCreation, startedAt: startedAt, succeeded: true)
                    HapticsManager.shared.playNotification(type: .success)
                    isPresented = false
                    return
                }

                isCreating = true

                Task {
                    do {
                        let group = try await CleaveAPI.shared.createGroup(
                            name: trimmedName,
                            isCollaborative: isCollaborative,
                            memberIDs: isCollaborative ? selectedMembers.map(\.id) : []
                        )
                        await MainActor.run {
                            ProductMetrics.record(.collaborativeGroupCreation, startedAt: startedAt, succeeded: true)
                            store.replace(with: group)
                            isPresented = false
                        }
                    } catch {
                        await MainActor.run {
                            ProductMetrics.record(.collaborativeGroupCreation, startedAt: startedAt, succeeded: false)
                            ErrorManager.shared.showError("Failed to create group: \(error.localizedDescription)")
                            isCreating = false
                        }
                    }
                }
            }) {
                ZStack {
                    if isCreating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(isCollaborative ? "Create Collaborative Group" : "Create Local Group")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.accentTeal)
                    .cornerRadius(16)
                    .padding(.horizontal, 30)
            }
            .disabled(
                isCreating
                || newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (!isCollaborative
                    && localMemberNames.isEmpty
                    && localMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
            .padding(.bottom, 20)
        }
        }
        .background(DesignSystem.canvasBeige.edgesIgnoringSafeArea(.all))
        .presentationDetents([.height(560), .large], selection: $sheetDetent)
    }

    private var localMembersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People in this group")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.black)

            Text("Add everyone as they appear on the receipt. They do not need a Cleave account.")
                .font(.system(size: 12))
                .foregroundColor(.black.opacity(0.6))

            HStack(spacing: 10) {
                TextField("Name", text: $localMemberName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(addPendingLocalMember)
                    .padding(12)
                    .background(Color.black.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button(action: addPendingLocalMember) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(DesignSystem.accentNavy)
                        .clipShape(Circle())
                }
                .disabled(localMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !localMemberNames.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(localMemberNames, id: \.self) { name in
                        HStack(spacing: 6) {
                            Text(name)
                            Button {
                                localMemberNames.removeAll { $0 == name }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DesignSystem.accentNavy)
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 30)
    }

    private func addPendingLocalMember() {
        let name = localMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let exists = localMemberNames.contains {
            $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if !exists { localMemberNames.append(name) }
        localMemberName = ""
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight), points)
    }
}
