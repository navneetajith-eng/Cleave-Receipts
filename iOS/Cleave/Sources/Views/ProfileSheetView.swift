import PhotosUI
import SwiftUI
import UIKit

struct ProfileSheetView: View {
    @Binding var isPresented: Bool

    @State private var profile: Profile?
    @State private var friends: [Profile] = []
    @State private var username = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var isSaving = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.canvasBeige.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        avatarEditor

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Username")
                                .sectionLabel()

                            HStack(spacing: 12) {
                                TextField("Username", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(14)
                                    .background(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                Button("Save") {
                                    Task { await saveUsername() }
                                }
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .frame(height: 48)
                                .background(DesignSystem.accentNavy)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .disabled(isSaving || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Friends")
                                    .sectionLabel()
                                Spacer()
                                Text("\(friends.count)")
                                    .font(.caption.bold())
                                    .foregroundColor(.black.opacity(0.45))
                            }

                            if friends.isEmpty {
                                Text("People from your collaborative groups will appear here.")
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundColor(.black.opacity(0.55))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(18)
                                    .background(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                VStack(spacing: 1) {
                                    ForEach(friends) { friend in
                                        HStack(spacing: 12) {
                                            ProfileAvatarView(profileID: friend.id, fallbackName: friend.displayName, size: 42)
                                            Text(friend.displayName)
                                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            Spacer()
                                        }
                                        .padding(14)
                                        .background(.white)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .task { await loadProfile() }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await saveAvatar(image)
            }
        }
    }

    private var avatarEditor: some View {
        VStack(spacing: 12) {
            Group {
                if let avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                } else if let profile {
                    ProfileAvatarView(profileID: profile.id, fallbackName: profile.displayName, size: 104)
                } else {
                    Circle().fill(Color.black.opacity(0.12))
                }
            }
            .frame(width: 104, height: 104)
            .clipShape(Circle())

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Change photo", systemImage: "camera.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.accentNavy)
            }
            .disabled(isSaving)
        }
        .padding(.top, 20)
    }

    private func loadProfile() async {
        isLoading = true
        async let loadedProfile = CleaveAPI.shared.fetchCurrentProfile()
        async let loadedFriends = CleaveAPI.shared.fetchFriends()
        do {
            let (newProfile, newFriends) = try await (loadedProfile, loadedFriends)
            profile = newProfile
            friends = newFriends
            username = newProfile.username ?? ""
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
        isLoading = false
    }

    private func saveUsername() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await CleaveAPI.shared.updateProfile(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            HapticsManager.shared.playNotification(type: .success)
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }

    private func saveAvatar(_ image: UIImage) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await CleaveAPI.shared.updateProfileAvatar(image: image)
            avatarImage = image
            HapticsManager.shared.playNotification(type: .success)
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }
}

struct ProfileAvatarView: View {
    let profileID: UUID
    let fallbackName: String
    var size: CGFloat = 44

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.85))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Text(String(fallbackName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .task(id: profileID) {
            guard let data = try? await CleaveAPI.shared.fetchProfileAvatar(profileID: profileID) else { return }
            image = UIImage(data: data)
        }
    }
}

private extension View {
    func sectionLabel() -> some View {
        font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(.black.opacity(0.5))
    }
}
