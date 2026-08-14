import SwiftUI

struct CollaborativeSearchSheetView: View {
    @Binding var selectedMembers: [Profile]
    var isEmbedded: Bool = false
    var onInvite: ((Profile) -> Void)? = nil
    var isAlreadyInvited: ((Profile) -> Bool)? = nil

    @State private var searchText = ""
    @State private var searchResults: [Profile] = []
    @State private var isSearching = false
    @Environment(\.presentationMode) var presentationMode

    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            if !isEmbedded {
                HStack {
                    Text("Add Friends")
                        .font(DesignSystem.displayFont(24))
                        .foregroundColor(DesignSystem.ink)
                    Spacer()
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color.black.opacity(0.5))
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
            } else {
                Text("Search Cleave accounts")
                    .font(DesignSystem.titleFont(17))
                    .foregroundColor(DesignSystem.ink)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Selected Members Pill List
            if !selectedMembers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(selectedMembers) { member in
                            HStack {
                                Text(member.preferredName)
                                    .font(DesignSystem.titleFont(14))
                                    .foregroundColor(.white)
                                Button(action: {
                                    selectedMembers.removeAll(where: { $0.id == member.id })
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DesignSystem.accentNavy)
                            .cornerRadius(20)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }

            // Search Bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignSystem.inkMuted)
                TextField(
                    "Search by username",
                    text: $searchText,
                    prompt: Text("Search by username").foregroundStyle(DesignSystem.ink.opacity(0.34))
                )
                    .font(DesignSystem.bodyFont(16))
                    .foregroundStyle(DesignSystem.ink)
                    .tint(DesignSystem.accentTeal)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        performSearch(query: newValue)
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(DesignSystem.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignSystem.hairline, lineWidth: 1))
            .padding(.horizontal, 24)

            // Results List
            ScrollView {
                VStack(spacing: 12) {
                    if isSearching {
                        VStack(spacing: 8) {
                            ForEach(0..<4, id: \.self) { _ in
                                SearchRowSkeletonView()
                            }
                        }
                    } else if searchResults.isEmpty && !searchText.isEmpty {
                        Text("No users found.")
                            .foregroundColor(Color.black.opacity(0.5))
                            .padding()
                    } else {
                        ForEach(searchResults) { profile in
                            HStack {
                                Circle()
                                    .fill(DesignSystem.accentTeal)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(String(profile.preferredName.prefix(1)).uppercased())
                                            .foregroundColor(.black)
                                            .font(.headline)
                                    )

                                VStack(alignment: .leading) {
                                    Text(profile.preferredName)
                                        .font(DesignSystem.titleFont(16))
                                        .foregroundColor(DesignSystem.ink)
                                    Text("@\(profile.username ?? "member")")
                                        .font(DesignSystem.bodyFont(12))
                                        .foregroundColor(DesignSystem.inkMuted)
                                }

                                Spacer()

                                if let onInvite = onInvite, let isAlreadyInvited = isAlreadyInvited {
                                    if isAlreadyInvited(profile) {
                                        Text("Invited")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(Color.black.opacity(0.4))
                                    } else {
                                        Button(action: {
                                            onInvite(profile)
                                        }) {
                                            Text("Invite")
                                                .font(.system(size: 14, weight: .bold))
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(DesignSystem.accentNavy)
                                                .foregroundColor(.white)
                                                .clipShape(Capsule())
                                        }
                                    }
                                } else {
                                    if selectedMembers.contains(where: { $0.id == profile.id }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(DesignSystem.accentNavy)
                                    } else {
                                        Button(action: {
                                            selectedMembers.append(profile)
                                        }) {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundColor(DesignSystem.accentTeal)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            loadFriends()
        }
    }

    private func performSearch(query: String) {
        searchTask?.cancel()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 2 else {
            if normalizedQuery.isEmpty {
                loadFriends()
            } else {
                searchResults = []
                isSearching = false
            }
            return
        }
        searchTask = Task {
            isSearching = true
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                searchResults = try await CleaveAPI.shared.searchProfiles(query: normalizedQuery)
            } catch {
                if !Task.isCancelled {
                    print("Search error: \(error)")
                }
            }
            if !Task.isCancelled {
                isSearching = false
            }
        }
    }

    private func loadFriends() {
        searchTask?.cancel()
        searchTask = Task {
            isSearching = true
            do {
                searchResults = try await CleaveAPI.shared.fetchFriends()
            } catch {
                if !Task.isCancelled { searchResults = [] }
            }
            if !Task.isCancelled { isSearching = false }
        }
    }
}
