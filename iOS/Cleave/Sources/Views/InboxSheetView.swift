import SwiftUI

struct InboxSheetView: View {
    @Binding var isPresented: Bool
    @Binding var appState: AppState
    @Binding var items: [InboxItem]

    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.canvasBeige.ignoresSafeArea()

                if isLoading && items.isEmpty {
                    ProgressView("Loading Inbox…")
                } else if items.isEmpty {
                    EmptyStateView(
                        iconName: "tray",
                        title: "You're All Caught Up",
                        message: "Collaborative group updates will appear here."
                    )
                } else {
                    List {
                        ForEach(items) { item in
                            Button {
                                Task { await open(item) }
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: item.kind == "group_added" ? "person.3.fill" : "bell.fill")
                                        .foregroundColor(.white)
                                        .frame(width: 42, height: 42)
                                        .background(item.isRead ? Color.black.opacity(0.25) : DesignSystem.accentNavy)
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(item.title)
                                                .font(.system(size: 16, weight: item.isRead ? .semibold : .bold, design: .rounded))
                                                .foregroundColor(.black)
                                            Spacer()
                                            if !item.isRead {
                                                Circle()
                                                    .fill(DesignSystem.accentOrange)
                                                    .frame(width: 9, height: 9)
                                            }
                                        }
                                        Text(item.body)
                                            .font(.system(size: 14, design: .rounded))
                                            .foregroundColor(.black.opacity(0.58))
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.white)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .refreshable { await refresh() }
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await CleaveAPI.shared.fetchInbox()
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }

    private func open(_ item: InboxItem) async {
        if !item.isRead,
           let index = items.firstIndex(where: { $0.id == item.id }),
           let updated = try? await CleaveAPI.shared.markInboxItemRead(id: item.id) {
            items[index] = updated
        }
        if let groupID = item.groupId {
            isPresented = false
            appState = .groupDetail(group: groupID)
        }
    }
}
