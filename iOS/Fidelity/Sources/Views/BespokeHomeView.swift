import SwiftUI

struct BespokeHomeView: View {
    @Binding var appState: AppState
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore
    
    // Some colors to cycle through for groups
    let cardColors = [DesignSystem.accentSage, DesignSystem.accentSlate, DesignSystem.accentDustyRose, DesignSystem.accentMustard]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            HStack {
                Text("Your Groups")
                    .font(.system(size: 48, weight: .light, design: .serif))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Top right profile or settings icon
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 20))
                    )
            }
            .padding(.horizontal, 30)
            .padding(.top, 60)
            
            Text("Select a group to split receipts.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    
                    ForEach(Array(store.groups.enumerated()), id: \.element.id) { index, group in
                        let color = cardColors[index % cardColors.count]
                        
                        GroupCard(
                            title: group.name,
                            members: group.members.count,
                            color: color,
                            namespace: namespace,
                            id: group.id
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                appState = .groupDetail(group: group.id)
                            }
                        }
                    }
                    
                    // Add New Group Card (static for now)
                    VStack {
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundColor(.white)
                        Spacer()
                        Text("New Group")
                            .font(.system(size: 20, weight: .regular, design: .serif))
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .frame(width: 200, height: 350)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [8]))
                            .foregroundColor(Color.white.opacity(0.3))
                    )
                    
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
            
            Spacer()
        }
    }
}

struct GroupCard: View {
    let title: String
    let members: Int
    let color: Color
    let namespace: Namespace.ID
    let id: String
    
    var body: some View {
        VStack(alignment: .leading) {
            // Icon
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "person.2.fill")
                        .foregroundColor(color)
                        .font(.system(size: 24))
                )
            
            Spacer()
            
            Text(title)
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundColor(.white)
                .matchedGeometryEffect(id: "groupTitle-\(id)", in: namespace)
            
            Text("\(members) members")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .matchedGeometryEffect(id: "groupSubtitle-\(id)", in: namespace)
        }
        .padding(30)
        .frame(width: 280, height: 400, alignment: .bottomLeading)
        .background(
            ZStack {
                Color.white.opacity(0.03)
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .matchedGeometryEffect(id: "groupBackground-\(id)", in: namespace)
        )
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .matchedGeometryEffect(id: "groupBorder-\(id)", in: namespace)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 30, y: 15)
    }
}
