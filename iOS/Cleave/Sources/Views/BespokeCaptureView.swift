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
    @State private var parsedCurrency: Currency = CurrencyManager.shared.currentCurrency

    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    @State private var showingScanner = false
    @State private var scannedImage: UIImage? = nil

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            CleaveReceiptWatermark(color: DesignSystem.accentOrange)
                .rotationEffect(.degrees(10))
                .position(x: 385, y: 155)
                .opacity(0.45)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    CleaveIconButton(systemName: "xmark", accessibilityText: "Close scanner") {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .groupDetail(group: groupId)
                        }
                    }
                    Spacer()

                    Text("SCAN")
                        .font(DesignSystem.labelFont(10))
                        .tracking(1.8)
                        .foregroundStyle(DesignSystem.accentTeal)
                }
                .padding(.horizontal, 22)
                .padding(.top, 58)

                CleaveSectionHeading(
                    showParsedItems ? "Receipt found" : "Capture the receipt",
                    eyebrow: showParsedItems ? "Ready to review" : nil,
                    detail: showParsedItems ? "We found \(parsedItems.count) items." : "Keep the full receipt inside the frame."
                )
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 18)

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(DesignSystem.surface.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(DesignSystem.hairline, lineWidth: 1)
                        )

                    ScannerCorners()
                        .padding(18)
                        .opacity(isScanning ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: isScanning)

                    if !isScanning && !showParsedItems {
                        VStack(spacing: 18) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 56, weight: .light))
                                .foregroundStyle(DesignSystem.accentTeal)

                            VStack(spacing: 9) {
                                ForEach([0.72, 0.9, 0.55], id: \.self) { width in
                                    Capsule()
                                        .fill(DesignSystem.ink.opacity(0.1))
                                        .frame(width: 150 * width, height: 7)
                                }
                            }
                        }
                    }

                    if isScanning && !showParsedItems {
                        VStack(spacing: 24) {
                            FlatScanningAnimation()

                            Text("Reading the receipt…")
                                .font(DesignSystem.titleFont(16))
                                .foregroundStyle(DesignSystem.ink)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    if showParsedItems {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(DesignSystem.accentTeal)
                                .padding(.bottom, 5)

                            ForEach(Array(parsedItems.prefix(3).enumerated()), id: \.element.id) { index, item in
                                HStack {
                                    Text(item.name)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(CurrencyManager.shared.format(item.price))
                                        .font(DesignSystem.titleFont(13))
                                }
                                .font(DesignSystem.bodyFont(14))
                                .foregroundStyle(DesignSystem.ink)
                                .padding(.horizontal, 14)
                                .frame(width: 250, height: 44)
                                .background(index.isMultiple(of: 2) ? DesignSystem.accentTeal.opacity(0.1) : DesignSystem.accentOrange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .padding(.horizontal, 22)

                if showParsedItems {
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .assignment(receiptId: parsedReceiptId, group: groupId, title: parsedTitle, items: parsedItems, assignments: [:], tax: parsedTax, tip: parsedTip, discount: parsedDiscount, currency: parsedCurrency)
                        }
                    }) {
                        HStack {
                            Text("Review items")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .black))
                        }
                    }
                    .primaryButton()
                    .buttonStyle(PressScaleButtonStyle())
                    .padding(.horizontal, 22)
                    .padding(.top, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            captureChoice(icon: "photo.on.rectangle", title: "Photo library", prominent: false)
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
                            captureChoice(icon: "camera.fill", title: "Open camera", prominent: true)
                        }
                        .buttonStyle(PressScaleButtonStyle())
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .opacity(isScanning ? 0 : 1)
                }
                Spacer(minLength: 18)
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

    private func captureChoice(icon: String, title: String, prominent: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
            Text(title)
                .font(DesignSystem.titleFont(14))
        }
        .foregroundStyle(prominent ? Color.white : DesignSystem.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(prominent ? DesignSystem.accentNavy : DesignSystem.surface.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(prominent ? Color.clear : DesignSystem.hairline, lineWidth: 1)
        )
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
                guard let userID = DemoMode.effectiveUserID else {
                    throw CleaveAPI.APIError.unauthorized
                }
                let parsed: ParsedReceiptResponse
                if DemoMode.isEnabled {
                    parsed = ParsedReceiptResponse(
                        vendorName: "Demo Market",
                        tax: 2.35,
                        tip: 0,
                        discount: 1,
                        total: 28.85,
                        lineItems: [
                            .init(description: "Sandwich", price: 12.50),
                            .init(description: "Iced Coffee", price: 7.00),
                            .init(description: "Fruit Bowl", price: 8.00)
                        ]
                    )
                } else {
                    parsed = try await CleaveAPI.shared.parseReceiptImage(image: image)
                }
                response = RemoteReceipt(
                    id: UUID(),
                    groupId: groupId,
                    title: parsed.vendorName,
                    adminId: userID,
                    currencyCode: CurrencyManager.shared.currentCurrency.rawValue,
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
                response = try await CleaveAPI.shared.uploadReceiptImage(
                    image: image,
                    groupID: groupId,
                    currency: CurrencyManager.shared.currentCurrency
                )
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
                    self.parsedCurrency = response.currency
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
                with: .color(DesignSystem.accentTeal.opacity(0.72)),
                style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

struct FlatScanningAnimation: View {
    @State private var scanOffset: CGFloat = -66

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Capsule()
                        .fill(DesignSystem.accentOrange)
                        .frame(width: 52, height: 8)
                    Spacer()
                    Circle()
                        .fill(DesignSystem.accentTeal)
                        .frame(width: 9, height: 9)
                }

                ForEach([0.82, 1.0, 0.62, 0.9], id: \.self) { width in
                    Capsule()
                        .fill(DesignSystem.ink.opacity(0.12))
                        .frame(width: 102 * width, height: 7)
                }
            }
            .padding(20)
            .frame(width: 142, height: 178)
            .background(DesignSystem.surface)
            .clipShape(ReceiptCardShape())
            .shadow(color: DesignSystem.ink.opacity(0.12), radius: 14, y: 8)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, DesignSystem.accentTeal, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 126, height: 3)
                .shadow(color: DesignSystem.accentTeal.opacity(0.5), radius: 5)
                .offset(y: scanOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                        scanOffset = 66
                    }
                }
        }
    }
}
