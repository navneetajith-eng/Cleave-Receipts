import PhotosUI
import SwiftUI
import UIKit

struct ProfileSheetView: View {
    @Binding var isPresented: Bool

    @State private var profile: Profile?
    @State private var friends: [Profile] = []
    @State private var username = ""
    @State private var paymentRegion = RegionManager.shared.currentRegion
    @State private var venmoUsername = PaymentPreferences.venmoUsername
    @State private var upiID = PaymentPreferences.upiID
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
                                TextField(
                                    "Username",
                                    text: $username,
                                    prompt: Text("Username").foregroundStyle(DesignSystem.ink.opacity(0.34))
                                )
                                    .font(DesignSystem.bodyFont(16))
                                    .foregroundStyle(DesignSystem.ink)
                                    .tint(DesignSystem.accentTeal)
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

                        paymentDetailsSection

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
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(friend.displayName)
                                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                                if let handle = paymentHandle(for: friend) {
                                                    Text(handle.display)
                                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                                        .foregroundStyle(DesignSystem.ink.opacity(0.55))
                                                } else {
                                                    Text("No payment handle shared")
                                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                                        .foregroundStyle(DesignSystem.ink.opacity(0.38))
                                                }
                                            }
                                            Spacer()
                                            if let handle = paymentHandle(for: friend) {
                                                Button {
                                                    UIPasteboard.general.string = handle.value
                                                    HapticsManager.shared.playNotification(type: .success)
                                                } label: {
                                                    Image(systemName: "doc.on.doc")
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundStyle(DesignSystem.accentNavy)
                                                        .frame(width: 36, height: 36)
                                                        .background(DesignSystem.canvasBeige, in: Circle())
                                                }
                                                .accessibilityLabel("Copy payment handle for \(friend.displayName)")
                                            }
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
        .preferredColorScheme(.light)
        .task { await loadProfile() }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await importAvatar(item) }
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

            PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .compatible) {
                Label("Change photo", systemImage: "camera.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.accentNavy)
            }
            .disabled(isSaving)
        }
        .padding(.top, 20)
    }

    @MainActor
    private func importAvatar(_ item: PhotosPickerItem) async {
        guard !isSaving else { return }
        isSaving = true
        defer {
            isSaving = false
            selectedPhoto = nil
        }
        do {
            let image = try await PhotoImport.loadImage(from: item)
            try await uploadAvatar(image.cleavePreparedForUpload(maxDimension: 1_200))
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
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
            if let regionCode = newProfile.regionCode,
               let remoteRegion = AppRegion(rawValue: regionCode) {
                PaymentPreferences.hydrate(
                    region: remoteRegion,
                    venmo: newProfile.venmoUsername,
                    upi: newProfile.upiId
                )
                paymentRegion = remoteRegion
                venmoUsername = newProfile.venmoUsername ?? ""
                upiID = newProfile.upiId ?? ""
            } else {
                paymentRegion = RegionManager.shared.currentRegion
                venmoUsername = PaymentPreferences.venmoUsername
                upiID = PaymentPreferences.upiID
            }
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

    @MainActor
    private func uploadAvatar(_ image: UIImage) async throws {
        profile = try await CleaveAPI.shared.updateProfileAvatar(image: image)
        avatarImage = image
        HapticsManager.shared.playNotification(type: .success)
    }

    private var paymentDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Get paid")
                    .sectionLabel()
                Spacer()
                Text("\(paymentRegion.flag) \(paymentRegion.currency.rawValue)")
                    .font(.caption.bold())
                    .foregroundColor(.black.opacity(0.45))
            }

            VStack(alignment: .leading, spacing: 12) {
                Label(paymentRegion.settlementMethod.displayName, systemImage: paymentRegion.settlementMethod.iconName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignSystem.accentNavy)

                switch paymentRegion {
                case .unitedStates:
                    TextField(
                        "Venmo username",
                        text: $venmoUsername,
                        prompt: Text("Venmo username").foregroundStyle(DesignSystem.ink.opacity(0.34))
                    )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .paymentProfileField()
                case .india:
                    TextField(
                        "UPI ID (name@bank)",
                        text: $upiID,
                        prompt: Text("UPI ID (name@bank)").foregroundStyle(DesignSystem.ink.opacity(0.34))
                    )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .paymentProfileField()
                case .unitedArabEmirates:
                    Text("Aani needs no payment details. Cleave opens its official App Store page when you settle.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.black.opacity(0.55))
                        .lineSpacing(3)
                }

                Label(
                    "Cleave checks the format, not ownership. This handle is shared only with people in your collaborative groups so they can pay you back.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DesignSystem.ink.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await savePaymentDetails() }
                } label: {
                    Text("Save payment details")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DesignSystem.accentNavy, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isSaving || !PaymentPreferences.isComplete(for: paymentRegion, venmo: venmoUsername, upi: upiID))
                .opacity(PaymentPreferences.isComplete(for: paymentRegion, venmo: venmoUsername, upi: upiID) ? 1 : 0.45)
            }
            .padding(16)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func savePaymentDetails() async {
        guard !isSaving,
              PaymentPreferences.isComplete(for: paymentRegion, venmo: venmoUsername, upi: upiID) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await CleaveAPI.shared.updatePaymentDetails(
                region: paymentRegion,
                venmoUsername: venmoUsername,
                upiID: upiID
            )
            PaymentPreferences.save(region: paymentRegion, venmo: venmoUsername, upi: upiID)
            PaymentPreferences.markSynced()
            HapticsManager.shared.playNotification(type: .success)
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }

    private func paymentHandle(for friend: Profile) -> (display: String, value: String)? {
        switch friend.regionCode.flatMap(AppRegion.init(rawValue:)) {
        case .unitedStates:
            return friend.venmoUsername.map { ("Venmo @\($0)", "@\($0)") }
        case .india:
            return friend.upiId.map { ("UPI \($0)", $0) }
        default:
            return nil
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

    func paymentProfileField() -> some View {
        font(DesignSystem.bodyFont(16))
            .foregroundStyle(DesignSystem.ink)
            .tint(DesignSystem.accentTeal)
            .padding(14)
            .background(DesignSystem.canvasBeige.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
