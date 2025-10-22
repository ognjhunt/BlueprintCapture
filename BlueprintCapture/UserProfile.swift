import Foundation

struct UserProfile: Identifiable, Codable {
    let id = UUID()
    var fullName: String
    var email: String
    var phoneNumber: String
    var company: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case email
        case phoneNumber = "phone_number"
        case company
    }

    init(fullName: String, email: String, phoneNumber: String, company: String) {
        self.fullName = fullName
        self.email = email
        self.phoneNumber = phoneNumber
        self.company = company
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fullName = try container.decode(String.self, forKey: .fullName)
        self.email = try container.decode(String.self, forKey: .email)
        self.phoneNumber = try container.decode(String.self, forKey: .phoneNumber)
        self.company = try container.decode(String.self, forKey: .company)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fullName, forKey: .fullName)
        try container.encode(email, forKey: .email)
        try container.encode(phoneNumber, forKey: .phoneNumber)
        try container.encode(company, forKey: .company)
    }
}

extension UserProfile {
    static let placeholder = UserProfile(fullName: "", email: "", phoneNumber: "", company: "")
    static let sample = UserProfile(fullName: "Jordan Smith", email: "jordan@example.com", phoneNumber: "+1 (415) 555-0101", company: "Blueprint Capture")
}
