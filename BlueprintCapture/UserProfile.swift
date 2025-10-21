import Foundation

struct UserProfile: Identifiable {
    let id = UUID()
    var fullName: String
    var email: String
    var phoneNumber: String
    var company: String
}

extension UserProfile {
    static let placeholder = UserProfile(fullName: "", email: "", phoneNumber: "", company: "")
    static let sample = UserProfile(fullName: "Jordan Smith", email: "jordan@example.com", phoneNumber: "+1 (415) 555-0101", company: "Blueprint Capture")
}
