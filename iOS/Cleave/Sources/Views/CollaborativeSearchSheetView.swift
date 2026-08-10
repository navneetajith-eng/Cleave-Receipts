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
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
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
                Text("Add Friends")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Selected Members Pill List
            if !selectedMembers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(selectedMembers) { member in
                            HStack {
                                Text(member.username ?? "Unknown")
                                    .font(.system(size: 14))
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
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.black.opacity(0.5))
                TextField("Search by username...", text: $searchText)
                    .foregroundColor(.black)
                    .onChange(of: searchText) { _, newValue in
                        performSearch(query: newValue)
                    }
            }
            .padding()
            .background(Color.black.opacity(0.1))
            .cornerRadius(16)
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
                                        Text(String(profile.username?.prefix(1).uppercased() ?? "?"))
                                            .foregroundColor(.black)
                                            .font(.headline)
                                    )

                                VStack(alignment: .leading) {
                                    Text(profile.username ?? "Unknown")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(.black)
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
            // Load recently discoverable profiles before the first search.
            performSearch(query: "")
        }
    }

    private func performSearch(query: String) {
        searchTask?.cancel()
        searchTask = Task {
            isSearching = true
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                if query.isEmpty {
                    searchResults = try await CleaveAPI.shared.searchProfiles(query: "")
                } else {
                    searchResults = try await CleaveAPI.shared.searchProfiles(query: query)
                }
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
}
