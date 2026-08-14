import PhotosUI
import SwiftUI
import UIKit

struct ProfileSheetView: View {
    @Binding var isPresented: Bool

    @State private var profile: Profile?
    @State private var friends: [Profile] = []
    @State private var selectedFriend: Profile?
    @State private var displayName = ""
    @State private var username = ""
    @State private var paymentRegion = RegionManager.shared.currentRegion
    @State private var venmoUsername = PaymentPreferences.venmoUsername
    @State private var upiID = PaymentPreferences.upiID
    @State private var aaniID = PaymentPreferences.aaniID
    @State private var ageBand = AgePreferences.ageBand ?? .adult
    @State private var avatarVisibility = ProfileVisibility.sharedGroups
    @State private var paymentVisibility = ProfileVisibility.sharedGroups
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var savedSnapshot: ProfileFormSnapshot?
    @State private var pendingAvatarImage: UIImage?
    @State private var showingDiscardConfirmation = false
    @State private var showingSavedToast = false
    @FocusState private var focusedField: ProfileFormField?

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.canvasBeige.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        avatarEditor

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Display name")
                                .sectionLabel()

                            TextField(
                                "Display name",
                                text: $displayName,
                                prompt: Text("What friends should call you").foregroundStyle(DesignSystem.ink.opacity(0.34))
                            )
                                .font(DesignSystem.bodyFont(16))
                                .foregroundStyle(DesignSystem.ink)
                                .tint(DesignSystem.accentTeal)
                                .textInputAutocapitalization(.words)
                                .focused($focusedField, equals: .displayName)
                                .padding(16)
                                .background(DesignSystem.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignSystem.hairline, lineWidth: 1))

                            Text("Username")
                                .sectionLabel()

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
                                .focused($focusedField, equals: .username)
                                .padding(16)
                                .background(DesignSystem.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignSystem.hairline, lineWidth: 1))
                        }

                        profilePreferencesSection
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
                                        Button {
                                            selectedFriend = friend
                                        } label: {
                                            HStack(spacing: 12) {
                                                ProfileAvatarView(profileID: friend.id, fallbackName: friend.preferredName, size: 42)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(friend.preferredName)
                                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                                        .foregroundStyle(DesignSystem.ink)
                                                    Text("@\(friend.username ?? "member")")
                                                        .font(DesignSystem.bodyFont(12))
                                                        .foregroundStyle(DesignSystem.inkMuted)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(DesignSystem.inkMuted)
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .padding(14)
                                        .background(.white)
                                        .buttonStyle(.plain)
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
                    Button("Done") { requestDismissal() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .safeAreaInset(edge: .bottom) { saveChangesBar }
        .overlay(alignment: .top) {
            if showingSavedToast {
                Label("Changes saved", systemImage: "checkmark.circle.fill")
                    .font(DesignSystem.titleFont(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(DesignSystem.accentTeal, in: Capsule())
                    .shadow(color: DesignSystem.accentTeal.opacity(0.25), radius: 12, y: 6)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("Discard unsaved changes?", isPresented: $showingDiscardConfirmation) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard changes", role: .destructive) { isPresented = false }
        } message: {
            Text("Your profile, privacy, payment, and selected photo changes have not been saved.")
        }
        .task { await loadProfile() }
        .sheet(item: $selectedFriend) { friend in
            FriendProfileSheetView(friend: friend)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                defer { selectedPhoto = nil }
                do {
                    let image = try await PhotoImport.loadImage(from: item)
                        .cleavePreparedForUpload(maxDimension: 1_200)
                    avatarImage = image
                    pendingAvatarImage = image
                } catch {
                    ErrorManager.shared.showError(error.localizedDescription)
                }
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
                    ProfileAvatarView(profileID: profile.id, fallbackName: profile.preferredName, size: 104)
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

    private func loadProfile() async {
        isLoading = true
        async let loadedProfile = CleaveAPI.shared.fetchCurrentProfile()
        async let loadedFriends = CleaveAPI.shared.fetchFriends()
        do {
            let (newProfile, newFriends) = try await (loadedProfile, loadedFriends)
            profile = newProfile
            friends = newFriends
            displayName = newProfile.preferredName
            username = newProfile.username ?? ""
            paymentRegion = newProfile.regionCode.flatMap(AppRegion.init(rawValue:)) ?? RegionManager.shared.currentRegion
            venmoUsername = newProfile.venmoUsername ?? PaymentPreferences.venmoUsername
            upiID = newProfile.upiId ?? PaymentPreferences.upiID
            aaniID = newProfile.aaniId ?? PaymentPreferences.aaniID
            ageBand = newProfile.ageBand.flatMap(AgeBand.init(rawValue:)) ?? AgePreferences.ageBand ?? .adult
            avatarVisibility = newProfile.avatarVisibility.flatMap(ProfileVisibility.init(rawValue:)) ?? .sharedGroups
            paymentVisibility = newProfile.paymentVisibility.flatMap(ProfileVisibility.init(rawValue:)) ?? .sharedGroups
            PaymentPreferences.hydrate(
                region: paymentRegion,
                venmo: venmoUsername,
                upi: upiID,
                aani: aaniID
            )
            savedSnapshot = currentSnapshot
            pendingAvatarImage = nil
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
        isLoading = false
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
                Label("Payment handles", systemImage: "wallet.pass.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignSystem.accentNavy)

                paymentHandleField("Venmo username", text: $venmoUsername, field: .venmo)
                paymentHandleField("Google Pay UPI ID (name@bank)", text: $upiID, field: .upi, keyboard: .emailAddress)
                paymentHandleField("Aani ID or mobile number", text: $aaniID, field: .aani, keyboard: .phonePad)

                Text("Add any combination. Empty handles are simply hidden.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.48))

            }
            .padding(16)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var profilePreferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile controls")
                .sectionLabel()
            VStack(alignment: .leading, spacing: 22) {
                themedPicker(
                    title: "Age range",
                    detail: "Used for age-appropriate access—not shown publicly.",
                    selection: $ageBand
                )
                themedPicker(
                    title: "Photo visibility",
                    detail: "Choose who can load your profile photo.",
                    selection: $avatarVisibility
                )
                themedPicker(
                    title: "Payment visibility",
                    detail: "Your handles only appear to the audience you choose.",
                    selection: $paymentVisibility
                )

                Text("Your username remains visible inside groups so members can allocate receipt items correctly.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.48))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func themedPicker<Value>(
        title: String,
        detail: String,
        selection: Binding<Value>
    ) -> some View where Value: CaseIterable & Identifiable & Hashable, Value.AllCases: RandomAccessCollection, Value.AllCases.Element == Value {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DesignSystem.titleFont(15))
                .foregroundStyle(DesignSystem.ink)
            Text(detail)
                .font(DesignSystem.bodyFont(12))
                .foregroundStyle(DesignSystem.inkMuted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                ForEach(Value.allCases) { value in
                    Button {
                        selection.wrappedValue = value
                        HapticsManager.shared.playImpact(style: .light)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: selection.wrappedValue == value ? "checkmark.circle.fill" : "circle")
                            Text(preferenceLabel(value))
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                        }
                        .font(DesignSystem.titleFont(12))
                        .foregroundStyle(selection.wrappedValue == value ? Color.white : DesignSystem.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 10)
                        .background(
                            selection.wrappedValue == value ? DesignSystem.accentNavy : DesignSystem.fieldSurface,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
            }
        }
    }

    private func preferenceLabel<Value>(_ value: Value) -> String {
        if let visibility = value as? ProfileVisibility { return visibility.displayName }
        if let age = value as? AgeBand { return age.displayName }
        return String(describing: value)
    }

    private func paymentHandleField(
        _ title: String,
        text: Binding<String>,
        field: ProfileFormField,
        keyboard: UIKeyboardType = .asciiCapable
    ) -> some View {
        TextField(
            title,
            text: text,
            prompt: Text(title).foregroundStyle(DesignSystem.ink.opacity(0.34))
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(keyboard)
        .focused($focusedField, equals: field)
        .paymentProfileField()
    }

    private var paymentHandlesAreValid: Bool {
        (venmoUsername.isEmpty || PaymentPreferences.isValidVenmo(venmoUsername))
            && (upiID.isEmpty || PaymentPreferences.isValidUPI(upiID))
            && (aaniID.isEmpty || PaymentPreferences.isValidAani(aaniID))
    }

    private var currentSnapshot: ProfileFormSnapshot {
        ProfileFormSnapshot(
            displayName: displayName,
            username: username,
            region: paymentRegion,
            venmo: venmoUsername,
            upi: upiID,
            aani: aaniID,
            ageBand: ageBand,
            avatarVisibility: avatarVisibility,
            paymentVisibility: paymentVisibility
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let savedSnapshot else { return false }
        return savedSnapshot != currentSnapshot || pendingAvatarImage != nil
    }

    private var formIsValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && paymentHandlesAreValid
            && ageBand != .under13
    }

    private var saveChangesBar: some View {
        VStack(spacing: 7) {
            Button {
                Task { await saveChanges() }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(.white) }
                    Text(isSaving ? "Saving…" : "Save changes")
                    Spacer()
                    Image(systemName: hasUnsavedChanges ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                }
                .font(DesignSystem.titleFont(16))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DesignSystem.accentNavy, in: Capsule())
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(isSaving || !hasUnsavedChanges || !formIsValid)
            .opacity(hasUnsavedChanges && formIsValid ? 1 : 0.48)

            if ageBand == .under13 {
                Text("Cleave's internal beta currently supports ages 13 and older.")
                    .font(DesignSystem.bodyFont(11))
                    .foregroundStyle(DesignSystem.accentOrange)
            } else if hasUnsavedChanges {
                Text("Saves profile, privacy, payment handles, and your selected photo.")
                    .font(DesignSystem.bodyFont(11))
                    .foregroundStyle(DesignSystem.inkMuted)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func requestDismissal() {
        focusedField = nil
        if hasUnsavedChanges {
            showingDiscardConfirmation = true
        } else {
            isPresented = false
        }
    }

    @MainActor
    private func saveChanges() async {
        guard !isSaving, hasUnsavedChanges, formIsValid else { return }
        focusedField = nil
        isSaving = true
        defer { isSaving = false }
        do {
            var savedProfile = try await CleaveAPI.shared.updateProfileSettings(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                ageBand: ageBand,
                avatarVisibility: avatarVisibility,
                paymentVisibility: paymentVisibility,
                region: paymentRegion,
                venmoUsername: venmoUsername,
                upiID: upiID,
                aaniID: aaniID
            )
            if let pendingAvatarImage {
                savedProfile = try await CleaveAPI.shared.updateProfileAvatar(image: pendingAvatarImage)
                NotificationCenter.default.post(name: .profileAvatarDidChange, object: savedProfile.id)
            }
            profile = savedProfile
            displayName = savedProfile.preferredName
            username = savedProfile.username ?? username.trimmingCharacters(in: .whitespacesAndNewlines)
            PaymentPreferences.save(region: paymentRegion, venmo: venmoUsername, upi: upiID, aani: aaniID)
            PaymentPreferences.markSynced()
            AgePreferences.ageBand = ageBand
            self.pendingAvatarImage = nil
            savedSnapshot = currentSnapshot
            HapticsManager.shared.playNotification(type: .success)
            withAnimation { showingSavedToast = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { withAnimation { showingSavedToast = false } }
            }
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }
}

private enum ProfileFormField: Hashable {
    case displayName, username, venmo, upi, aani
}

private struct ProfileFormSnapshot: Equatable {
    let displayName: String
    let username: String
    let region: AppRegion
    let venmo: String
    let upi: String
    let aani: String
    let ageBand: AgeBand
    let avatarVisibility: ProfileVisibility
    let paymentVisibility: ProfileVisibility
}

private struct FriendProfileSheetView: View {
    let friend: Profile

    @Environment(\.dismiss) private var dismiss
    @State private var details: Profile?
    @State private var isLoading = true

    private var profile: Profile { details ?? friend }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.canvasBeige.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        ProfileAvatarView(
                            profileID: profile.id,
                            fallbackName: profile.preferredName,
                            size: 104
                        )

                        VStack(spacing: 5) {
                            Text(profile.preferredName)
                                .font(DesignSystem.displayFont(30))
                                .foregroundStyle(DesignSystem.ink)
                            Text("@\(profile.username ?? "member")")
                                .font(DesignSystem.bodyFont(15))
                                .foregroundStyle(DesignSystem.inkMuted)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Label("PAYMENT PROFILE", systemImage: "wallet.pass.fill")
                                .font(DesignSystem.labelFont(10))
                                .tracking(1.4)
                                .foregroundStyle(DesignSystem.accentOrange)

                            if let regionCode = profile.regionCode,
                               let region = AppRegion(rawValue: regionCode) {
                                detailRow(icon: "globe", label: "Region", value: "\(region.flag) \(region.displayName)")
                            }
                            if let venmo = profile.venmoUsername {
                                detailRow(icon: "v.square.fill", label: "Venmo", value: "@\(venmo)")
                            }
                            if let upi = profile.upiId {
                                detailRow(icon: "indianrupeesign.circle.fill", label: "Google Pay", value: upi)
                            }
                            if let aani = profile.aaniId {
                                detailRow(icon: "bolt.horizontal.circle.fill", label: "Aani", value: aani)
                            }

                            if !isLoading && profile.regionCode == nil && profile.venmoUsername == nil
                                && profile.upiId == nil && profile.aaniId == nil {
                                Label("Payment details are private", systemImage: "lock.fill")
                                    .font(DesignSystem.bodyFont(14))
                                    .foregroundStyle(DesignSystem.inkMuted)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(DesignSystem.hairline, lineWidth: 1))

                        Text("Only details this friend shares with mutual group members appear here.")
                            .font(DesignSystem.bodyFont(12))
                            .foregroundStyle(DesignSystem.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Friend profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(DesignSystem.titleFont(15))
                }
            }
        }
        .preferredColorScheme(.light)
        .task {
            defer { isLoading = false }
            details = try? await CleaveAPI.shared.fetchFriendProfile(id: friend.id)
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DesignSystem.accentTeal)
                .frame(width: 34, height: 34)
                .background(DesignSystem.accentTeal.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(DesignSystem.labelFont(8))
                    .tracking(0.9)
                    .foregroundStyle(DesignSystem.inkMuted)
                Text(value)
                    .font(DesignSystem.titleFont(14))
                    .foregroundStyle(DesignSystem.ink)
                    .textSelection(.enabled)
            }
            Spacer()
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
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileAvatarDidChange)) { notification in
            guard notification.object as? UUID == profileID else { return }
            Task { await reload() }
        }
    }

    @MainActor
    private func reload() async {
        guard let data = try? await CleaveAPI.shared.fetchProfileAvatar(profileID: profileID) else {
            image = nil
            return
        }
        image = UIImage(data: data)
    }
}

extension Notification.Name {
    static let profileAvatarDidChange = Notification.Name("cleave.profileAvatarDidChange")
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
