import SwiftUI

struct BespokeGroupDetailView: View {
    let groupName: String
    @Binding var appState: AppState
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore
    
    @State private var newMemberName: String = ""
    @State private var isAddingMember: Bool = false
    
    var group: GroupModel? {
        store.getGroup(id: groupName)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Expanded Background
            ZStack {
                Color.black.opacity(0.3)
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .matchedGeometryEffect(id: "groupBackground-\(groupName)", in: namespace)
            .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .stroke(Color.white.opacity(0.0), lineWidth: 1)
                    .matchedGeometryEffect(id: "groupBorder-\(groupName)", in: namespace)
            )
            .ignoresSafeArea()
            
            if let group = group {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                appState = .home
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 60)
                    
                    Text(group.name)
                        .font(.system(size: 64, weight: .regular, design: .serif))
                        .foregroundColor(.white)
                        .matchedGeometryEffect(id: "groupTitle-\(groupName)", in: namespace)
                        .padding(.horizontal, 30)
                    
                    Text("\(group.members.count) members")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .matchedGeometryEffect(id: "groupSubtitle-\(groupName)", in: namespace)
                        .padding(.horizontal, 30)
                    
                    // Horizontal scroll of members
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(group.members, id: \.self) { member in
                                VStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 60, height: 60)
                                        .overlay(
                                            Text(String(member.prefix(1)))
                                                .font(.system(size: 24, design: .serif))
                                                .foregroundColor(.white)
                                        )
                                    Text(member)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            
                            // Add Member Button / Field
                            if isAddingMember {
                                HStack {
                                    TextField("Name", text: $newMemberName)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(Capsule())
                                        .frame(width: 100)
                                    
                                    Button(action: {
                                        if !newMemberName.isEmpty {
                                            withAnimation {
                                                store.addMember(to: group.id, memberName: newMemberName)
                                                newMemberName = ""
                                                isAddingMember = false
                                            }
                                        }
                                    }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(DesignSystem.accentSage)
                                    }
                                }
                                .padding(.leading, 10)
                            } else {
                                Button(action: {
                                    withAnimation {
                                        isAddingMember = true
                                    }
                                }) {
                                    VStack {
                                        Circle()
                                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                            .foregroundColor(.white.opacity(0.5))
                                            .frame(width: 60, height: 60)
                                            .overlay(
                                                Image(systemName: "plus")
                                                    .foregroundColor(.white.opacity(0.8))
                                            )
                                        Text("Add")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 30)
                    }
                    .frame(height: 100)
                    
                    Spacer()
                    
                    // Action Area
                    VStack(spacing: 30) {
                        Text("No Recent Receipts.")
                            .font(.system(size: 24, weight: .light, design: .serif))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                appState = .capture(group: groupName)
                            }
                        }) {
                            HStack {
                                Image(systemName: "camera.viewfinder")
                                Text("Scan Receipt")
                            }
                        }
                        .primaryButton()
                    }
                    .padding(40)
                }
            }
        }
    }

    private func receiptHistoryCard(split: ReceiptSplit) -> some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        let subtotal = split.items.reduce(0) { $0 + $1.1 }
        let total = subtotal + split.tax + split.tip
        
        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(split.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Text(formatter.string(from: split.date))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                        Text("\(split.items.count) items")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        
                        if let rating = split.rating {
                            HStack(spacing: 2) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(star <= rating ? DesignSystem.accentMustard : .white.opacity(0.3))
                                }
                            }
                        }
                    }
                }
                Spacer()
                Text(String(format: "$%.2f", total))
                    .font(.system(.title3, design: .rounded))
                    .foregroundColor(DesignSystem.accentMustard)
            }
            
            if let photos = split.memoryPhotos, !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos.indices, id: \.self) { index in
                            if let image = UIImage(data: photos[index]) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
