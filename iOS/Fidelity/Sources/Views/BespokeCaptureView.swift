import SwiftUI
import PhotosUI

struct BespokeCaptureView: View {
    let groupName: String
    @Binding var appState: AppState
    var namespace: Namespace.ID
    
    @State private var isScanning = false
    @State private var showParsedItems = false
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var parsedItems: [(String, Double)] = []
    @State private var parsedTax: Double = 0
    @State private var parsedTip: Double = 0
    @State private var parsedTitle: String = ""
    
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    var body: some View {
        ZStack {
            // Mock Camera Viewfinder Background
            Color(white: 0.1).ignoresSafeArea()
            
            VStack {
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .groupDetail(group: groupName)
                        }
                    }) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 60)
                
                Spacer()
                
                // Edge Detection Bounding Box (Apple Document Scanner style)
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(isScanning ? 0.8 : 0.2), lineWidth: 2)
                        .frame(width: 300, height: 450)
                        .shadow(color: isScanning ? Color.white.opacity(0.5) : .clear, radius: 20)
                    
                    if isScanning {
                        // Subtle Glass Shimmer (No laser lines)
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.4), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 300, height: 450)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .offset(x: shimmerOffset * 300, y: shimmerOffset * 450)
                        .onAppear {
                            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                                shimmerOffset = 1.0
                            }
                            
                            performScan()
                        }
                    }
                    
                    // Parsed items organically popping out
                    if showParsedItems {
                        VStack(spacing: 8) {
                            ForEach(Array(parsedItems.prefix(3).enumerated()), id: \.element.0) { index, item in
                                let offsets: [(CGFloat, CGFloat)] = [(-20, -80), (40, 0), (-10, 80)]
                                let offset = index < offsets.count ? offsets[index] : (0, 0)
                                
                                Text("\(item.0)  $\(String(format: "%.2f", item.1))")
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .offset(x: offset.0, y: offset.1)
                            }
                        }
                        .foregroundColor(.white)
                        .font(.system(.subheadline, design: .serif).weight(.medium))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                
                Spacer()
                
                if showParsedItems {
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .assignment(group: groupName, title: parsedTitle, items: parsedItems, tax: parsedTax, tip: parsedTip)
                        }
                    }) {
                        Text("Review Items")
                    }
                    .primaryButton()
                    .padding(40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    HStack(spacing: 40) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .frame(width: 70, height: 70)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .onChange(of: selectedPhotoItem) { newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    await uploadAndParseImage(image)
                                }
                            }
                        }
                        
                        Button(action: {
                            isScanning = true
                        }) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.5), lineWidth: 4)
                                        .frame(width: 80, height: 80)
                                )
                        }
                        
                        // Placeholder for symmetry
                        Color.clear
                            .frame(width: 70, height: 70)
                    }
                    .padding(.bottom, 50)
                    .opacity(isScanning ? 0 : 1)
                }

            }
        }
    }
    
    private func uploadAndParseImage(_ image: UIImage) async {
        await MainActor.run { isScanning = true }
        
        do {
            let response = try await FidelityAPI.shared.uploadReceiptImage(image: image, groupID: groupName)
            let fetchedItems = response.line_items.map { ($0.description, $0.price) }
            
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    self.parsedTitle = response.vendor_name
                    self.parsedItems = fetchedItems
                    self.parsedTax = response.tax
                    self.parsedTip = response.tip
                    self.showParsedItems = true
                    self.isScanning = false
                }
            }
        } catch {
            print("Error scanning: \(error)")
            await MainActor.run {
                self.isScanning = false
            }
        }
    }
    
    private func performScan() {
        Task {
            do {
                // 1. Download sample receipt for simulator since we don't have a real camera
                guard let url = URL(string: "https://raw.githubusercontent.com/Azure-Samples/cognitive-services-REST-api-samples/master/curl/form-recognizer/contoso-receipt.png") else { return }
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return }
                
                // 2. Call local Python Backend with Gemini
                await uploadAndParseImage(image)
            } catch {
                print("Error getting sample image: \(error)")
                await MainActor.run {
                    self.isScanning = false
                }
            }
        }
    }
}
