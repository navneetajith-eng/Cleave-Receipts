import PhotosUI
import SwiftUI
import UIKit

enum PhotoImportError: LocalizedError {
    case unavailable
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Cleave couldn't load that photo. If it is stored in iCloud, wait for it to download or choose another image."
        case .unreadable:
            return "That file isn't a readable image. Please choose a different photo."
        }
    }
}

@MainActor
enum PhotoImport {
    static func loadImage(from item: PhotosPickerItem) async throws -> UIImage {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw PhotoImportError.unavailable
        }
        guard let image = UIImage(data: data) else {
            throw PhotoImportError.unreadable
        }
        return image
    }
}

extension UIImage {
    /// Normalizes orientation and bounds upload size for reliable real-device transfers.
    @MainActor
    func cleavePreparedForUpload(maxDimension: CGFloat = 2_400) -> UIImage {
        let largestDimension = max(size.width, size.height)
        let scale = largestDimension > maxDimension ? maxDimension / largestDimension : 1
        let targetSize = CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
