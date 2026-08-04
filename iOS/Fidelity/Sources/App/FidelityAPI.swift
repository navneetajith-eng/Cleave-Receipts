import Foundation
import UIKit

class FidelityAPI {
    static let shared = FidelityAPI()
    
    let baseURL = "http://localhost:8000/api"
    
    struct ReceiptResponse: Decodable {
        let id: String
        let vendor_name: String
        let tax: Double
        let tip: Double
        let total: Double
        let line_items: [LineItem]
        
        struct LineItem: Decodable {
            let id: String
            let description: String
            let price: Double
        }
    }
    
    func uploadReceiptImage(image: UIImage, groupID: String = "123") async throws -> ReceiptResponse {
        guard let url = URL(string: "\(baseURL)/receipts?group_id=\(groupID)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.cannotDecodeRawData)
        }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"receipt.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("API Error: \(String(data: data, encoding: .utf8) ?? "")")
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(ReceiptResponse.self, from: data)
    }
}
