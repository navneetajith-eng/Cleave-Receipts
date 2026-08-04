import Foundation
import SwiftUI

class AppStore: ObservableObject {
    @Published var groups: [GroupModel] = [
        GroupModel(id: "Roommates", name: "Roommates", members: ["Nav", "Sandra", "Alex"]),
        GroupModel(id: "Colleagues", name: "Colleagues", members: ["John", "Sarah", "Mike", "Emma", "David"])
    ]
    
    func addMember(to groupID: String, memberName: String) {
        if let index = groups.firstIndex(where: { $0.id == groupID }) {
            // Avoid duplicates
            if !groups[index].members.contains(memberName) {
                groups[index].members.append(memberName)
            }
        }
    }
    
    func saveSplit(to groupID: String, split: ReceiptSplit) {
        if let index = groups.firstIndex(where: { $0.id == groupID }) {
            objectWillChange.send()
            groups[index].history.append(split)
        }
    }
    
    func getGroup(id: String) -> GroupModel? {
        return groups.first(where: { $0.id == id })
    }
}

struct GroupModel: Identifiable {
    let id: String
    var name: String
    var members: [String]
    var history: [ReceiptSplit] = []
}

struct ReceiptSplit: Identifiable {
    let id = UUID()
    let date = Date()
    var title: String
    let items: [(String, Double)]
    let tax: Double
    let tip: Double
    let assignments: [Int: Set<String>]
    var rating: Int? = nil
    var memoryPhotos: [Data]? = nil
}
