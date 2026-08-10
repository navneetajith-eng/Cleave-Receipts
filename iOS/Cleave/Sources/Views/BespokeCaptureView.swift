import SwiftUI
import PhotosUI
import UIKit

struct BespokeCaptureView: View {
    let groupId: UUID
    @Binding var appState: AppState
    var namespace: Namespace.ID
    @EnvironmentObject private var store: AppStore

    @State private var isScanning = false
    @State private var showParsedItems = false
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var parsedItems: [ReceiptItem] = []
    @State private var parsedTax: Double = 0
    @State private var parsedTip: Double = 0
    @State private var parsedDiscount: Double = 0
    @State private var parsedTitle: String = ""
    @State private var parsedReceiptId: String = ""

    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    @State private var showingScanner = false
    @State private var scannedImage: UIImage? = nil

    var body: some View {
        ZStack {
            // Premium Beige Background
            DesignSystem.canvasBeige.ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .groupDetail(group: groupId)
                        }
                    }) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color.black.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 60)

                Spacer()

                // Minimalistic Apple Document Scanner corner brackets
                ZStack {
                    ScannerCorners()
                        .frame(width: 320, height: 480)
                        .opacity(isScanning ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: isScanning)

                    if isScanning && !showParsedItems {
                        VStack(spacing: 30) {
                            FlatScanningAnimation()

                            Text("Analyzing Receipt...")
                                .font(.system(.headline, design: .rounded))
                                .foregroundColor(DesignSystem.bgNavy)
                                .opacity(0.8)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Parsed items organically popping out
                    if showParsedItems {
                        VStack(spacing: 8) {
                            ForEach(Array(parsedItems.prefix(3).enumerated()), id: \.element.id) { index, item in
                                let offsets: [(CGFloat, CGFloat)] = [(-20, -80), (40, 0), (-10, 80)]
                                let offset = index < offsets.count ? offsets[index] : (0, 0)

                                Text("\(item.name)  \(CurrencyManager.shared.format(item.price))")
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .offset(x: offset.0, y: offset.1)
                            }
                        }
                        .foregroundColor(Color.black.opacity(0.85))
                        .font(.system(.subheadline, design: .serif).weight(.medium))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }

                Spacer()

                if showParsedItems {
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .assignment(receiptId: parsedReceiptId, group: groupId, title: parsedTitle, items: parsedItems, assignments: [:], tax: parsedTax, tip: parsedTip, discount: parsedDiscount)
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
                                .foregroundColor(Color.black.opacity(0.85))
                                .frame(width: 70, height: 70)
                                .background(Color.black.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    await uploadAndParseImage(image)
                                }
                            }
                        }

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showingScanner = true
                        }) {
                            // Native iOS Shutter Button Look
                            Circle()
                                .fill(Color.white)
                                .frame(width: 64, height: 64)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.1), lineWidth: 2)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 76, height: 76)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
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
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScanner(scannedImage: $scannedImage, isPresented: $showingScanner)
                .ignoresSafeArea()
        }
        .onChange(of: scannedImage) { _, newImage in
            if let image = newImage {
                Task {
                    await uploadAndParseImage(image)
                }
            }
        }
    }

    private func uploadAndParseImage(_ image: UIImage) async {
        let startedAt = Date()
        await MainActor.run { isScanning = true }

        let draft: ReceiptDraft
        do {
            draft = try store.stageReceiptImage(image, groupID: groupId)
        } catch {
            ErrorManager.shared.showError("Cleave couldn't save this photo on your device. Please free some storage and try again.")
            await MainActor.run { isScanning = false }
            return
        }

        do {
            let response: RemoteReceipt
            if let group = store.getGroup(id: groupId), !group.isCollaborative {
                guard let userID = SupabaseManager.shared.currentUser?.id else {
                    throw CleaveAPI.APIError.unauthorized
                }
                let parsed = try await CleaveAPI.shared.parseReceiptImage(image: image)
                response = RemoteReceipt(
                    id: UUID(),
                    groupId: groupId,
                    title: parsed.vendorName,
                    adminId: userID,
                    taxAmount: parsed.tax,
                    tipAmount: parsed.tip,
                    discountAmount: parsed.discount,
                    imageUrl: nil,
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    items: parsed.lineItems.map {
                        ReceiptItem(id: UUID().uuidString, name: $0.description, price: $0.price)
                    }
                )
                await MainActor.run { store.saveLocalReceipt(response) }
            } else {
                response = try await CleaveAPI.shared.uploadReceiptImage(image: image, groupID: groupId)
            }
            let fetchedItems = response.items

            await MainActor.run {
                ProductMetrics.record(.receiptCaptureToReview, startedAt: startedAt, succeeded: true)
                store.removeDraft(id: draft.id)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    self.parsedTitle = response.title
                    self.parsedReceiptId = response.id.uuidString
                    self.parsedItems = fetchedItems
                    self.parsedTax = response.taxAmount
                    self.parsedTip = response.tipAmount
                    self.parsedDiscount = response.discountAmount
                    self.showParsedItems = true
                    self.isScanning = false
                }
            }
        } catch {
            print("Error scanning: \(error)")
            await MainActor.run {
                ProductMetrics.record(.receiptCaptureToReview, startedAt: startedAt, succeeded: false)
                store.markDraftFailed(id: draft.id, message: error.localizedDescription)
                ErrorManager.shared.showError("Receipt saved on this device. Open the group and tap Retry when you're online.")
                self.isScanning = false
            }
        }
    }

    private func performScan() {
        // This is now unused because we use native DocumentScanner, but kept as a fallback method if needed
    }
}

// Minimalistic corner brackets mimicking Apple's native document scanner
struct ScannerCorners: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let length: CGFloat = 40
            let thickness: CGFloat = 4

            var path = Path()

            // Top Left
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))

            // Top Right
            path.move(to: CGPoint(x: w - length, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: length))

            // Bottom Right
            path.move(to: CGPoint(x: w, y: h - length))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w - length, y: h))

            // Bottom Left
            path.move(to: CGPoint(x: length, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: h - length))

            context.stroke(
                path,
                with: .color(Color.black.opacity(0.6)),
                style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

struct FlatScanningAnimation: View {
    @State private var offset: CGFloat = -40
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Flat Receipt
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .frame(width: 140, height: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DesignSystem.bgNavy, lineWidth: 6)
                )
                .overlay(
                    VStack(alignment: .leading, spacing: 16) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.bgNavy.opacity(0.3))
                            .frame(width: 80, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.bgNavy.opacity(0.3))
                            .frame(width: 100, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.bgNavy.opacity(0.3))
                            .frame(width: 60, height: 12)
                    }
                    .padding(.top, -20)
                )

            // Magnifying Glass
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60, weight: .bold))
                .foregroundColor(DesignSystem.accentTeal)
                .background(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 50, height: 50)
                )
                .shadow(color: DesignSystem.bgNavy.opacity(0.15), radius: 10, y: 10)
                .offset(x: offset, y: offset * 1.2)
                .scaleEffect(scale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        offset = 40
                        scale = 1.1
                    }
                }
        }
    }
}
