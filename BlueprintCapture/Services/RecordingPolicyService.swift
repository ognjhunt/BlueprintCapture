import Foundation

/// Represents the recording policy risk level for a venue
enum RecordingPolicyRisk: String, Codable, Comparable {
    case safe       // Known to allow recording or low-risk venue type
    case unknown    // No data available
    case caution    // Category suggests potential restrictions
    case restricted // Known chain/venue with explicit no-recording policy

    static func < (lhs: RecordingPolicyRisk, rhs: RecordingPolicyRisk) -> Bool {
        let order: [RecordingPolicyRisk] = [.safe, .unknown, .caution, .restricted]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Result of a recording policy check
struct RecordingPolicyResult {
    let risk: RecordingPolicyRisk
    let reason: String
    let requiresPermission: Bool
    let suggestedAction: String?

    static let safe = RecordingPolicyResult(
        risk: .safe,
        reason: "Venue type typically allows recording",
        requiresPermission: false,
        suggestedAction: nil
    )

    static let unknown = RecordingPolicyResult(
        risk: .unknown,
        reason: "Recording policy not known",
        requiresPermission: false,
        suggestedAction: "Verify recording policy before capture"
    )
}

/// Service that evaluates recording policies for venues
/// Uses a tiered approach:
/// 1. Hardcoded blocklist of known restrictive chains
/// 2. Category-based risk scoring
/// 3. (Optional) AI verification for ambiguous cases
final class RecordingPolicyService {

    static let shared = RecordingPolicyService()

    // MARK: - Known Restrictive Chains (Tier 1)
    // These are chains known to have explicit no-commercial-filming policies
    // Sources: Corporate policies, legal documents, venue codes of conduct

    /// Major retail chains with known no-recording/commercial-filming policies
    private let restrictedChains: Set<String> = [
        // Big Box Retailers
        "walmart", "wal-mart", "wal mart",
        "costco",
        "target",
        "sam's club", "sams club",
        "bj's", "bjs wholesale",

        // Department Stores
        "macy's", "macys",
        "nordstrom",
        "jcpenney", "jc penney", "j.c. penney",
        "kohl's", "kohls",
        "dillard's", "dillards",
        "neiman marcus",
        "saks fifth avenue", "saks",
        "bloomingdale's", "bloomingdales",

        // Electronics
        "best buy",
        "apple store", "apple",
        "microsoft store",

        // Home Improvement
        "home depot", "the home depot",
        "lowe's", "lowes",
        "menards",

        // Grocery (Major Chains)
        "whole foods", "whole foods market",
        "trader joe's", "trader joes",
        "kroger",
        "safeway",
        "albertsons",
        "publix",
        "h-e-b", "heb",
        "wegmans",
        "aldi",
        "lidl",
        "food lion",
        "stop & shop", "stop and shop",
        "giant", "giant eagle",
        "meijer",
        "winn-dixie", "winn dixie",
        "sprouts", "sprouts farmers market",

        // Pharmacies
        "cvs", "cvs pharmacy",
        "walgreens",
        "rite aid",

        // Warehouse/Membership
        "costco wholesale",

        // Specialty Retail
        "sephora",
        "ulta", "ulta beauty",
        "bath & body works", "bath and body works",
        "victoria's secret", "victorias secret",
        "lululemon",
        "nike",
        "foot locker",
        "finish line",
        "gamestop",
        "barnes & noble", "barnes and noble",

        // Furniture/Home
        "ikea",
        "rooms to go",
        "ashley furniture", "ashley homestore",
        "pottery barn",
        "crate & barrel", "crate and barrel",
        "williams-sonoma", "williams sonoma",
        "bed bath & beyond", "bed bath and beyond",

        // Convenience
        "7-eleven", "7 eleven", "7eleven",
        "circle k",
        "wawa",
        "sheetz",
        "quiktrip", "qt",
        "racetrac",
        "casey's",

        // Fast Food / Quick Service (often have policies)
        "mcdonald's", "mcdonalds",
        "starbucks",
        "chick-fil-a", "chick fil a",
        "chipotle",
        "panera", "panera bread",
        "dunkin", "dunkin donuts",
        "subway",
        "wendy's", "wendys",
        "burger king",
        "taco bell",
        "popeyes",
        "five guys",
        "shake shack",

        // Restaurants (Sit-down chains)
        "olive garden",
        "applebee's", "applebees",
        "chili's", "chilis",
        "outback steakhouse", "outback",
        "red lobster",
        "texas roadhouse",
        "cheesecake factory", "the cheesecake factory"
    ]

    /// Major mall operators with explicit spatial data capture restrictions
    private let restrictedMallOperators: Set<String> = [
        "simon", "simon property", "simon mall",
        "westfield",
        "brookfield", "brookfield properties",
        "macerich",
        "taubman",
        "unibail-rodamco-westfield", "urw",
        "federal realty",
        "kimco realty", "kimco"
    ]

    // MARK: - Category Risk Scoring (Tier 2)

    /// Place types that are generally safe for recording (owner-operated, public-facing)
    private let safeTypes: Set<String> = [
        "park",
        "parking",
        "tourist_attraction",
        "stadium",
        "museum",              // Many allow, but verify
        "art_gallery",
        "church",
        "cemetery",
        "campground",
        "rv_park",
        "zoo",
        "aquarium",
        "amusement_park",      // Though Disney etc. have restrictions
        "bowling_alley",
        "movie_rental",
        "laundry",
        "storage",
        "moving_company",
        "self_storage",        // Often owner-operated
        "real_estate_agency",
        "travel_agency",
        "insurance_agency",
        "accounting",
        "lawyer",
        "locksmith",
        "plumber",
        "electrician",
        "roofing_contractor",
        "general_contractor"
    ]

    /// Place types that typically require permission (commercial spaces)
    private let cautionTypes: Set<String> = [
        "shopping_mall",
        "department_store",
        "supermarket",
        "grocery_store",
        "grocery_or_supermarket",
        "convenience_store",
        "electronics_store",
        "clothing_store",
        "shoe_store",
        "jewelry_store",
        "home_goods_store",
        "furniture_store",
        "hardware_store",
        "book_store",
        "pet_store",
        "liquor_store",
        "pharmacy",
        "drugstore",
        "discount_store",
        "warehouse_store",
        "wholesale_store"
    ]

    /// Place types where recording is almost always restricted
    private let restrictedTypes: Set<String> = [
        "casino",
        "night_club",
        "strip_club",
        "adult_entertainment",
        "hospital",
        "doctor",
        "dentist",
        "physiotherapist",
        "health",
        "medical_lab",
        "courthouse",
        "local_government_office",
        "embassy",
        "police",
        "fire_station",
        "post_office",
        "bank",
        "atm",
        "finance",
        "school",
        "primary_school",
        "secondary_school",
        "university",
        "library",
        "preschool",
        "childcare",
        "child_care",
        "spa",
        "gym",
        "fitness_center"
    ]

    // MARK: - Cache

    /// Cache for AI verification results (persisted to UserDefaults)
    private var verificationCache: [String: RecordingPolicyResult] = [:]
    private let cacheKey = "RecordingPolicyCache"

    private init() {
        loadCache()
    }

    // MARK: - Public API

    /// Evaluates recording policy risk for a place
    /// - Parameters:
    ///   - name: Display name of the place
    ///   - types: Google Places types array
    ///   - placeId: Optional place ID for caching
    /// - Returns: Recording policy result with risk level and recommendations
    func evaluatePolicy(name: String, types: [String], placeId: String? = nil) -> RecordingPolicyResult {
        // Check cache first
        if let placeId = placeId, let cached = verificationCache[placeId] {
            return cached
        }

        // Tier 1: Check against known restrictive chains
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        for restrictedChain in restrictedChains {
            if normalizedName.contains(restrictedChain) {
                let result = RecordingPolicyResult(
                    risk: .restricted,
                    reason: "Known chain with no-commercial-filming policy",
                    requiresPermission: true,
                    suggestedAction: "Contact corporate office for filming permission"
                )
                if let placeId = placeId { cache(result, for: placeId) }
                return result
            }
        }

        // Check mall operators
        for mallOperator in restrictedMallOperators {
            if normalizedName.contains(mallOperator) {
                let result = RecordingPolicyResult(
                    risk: .restricted,
                    reason: "Mall operator with explicit spatial data capture restrictions",
                    requiresPermission: true,
                    suggestedAction: "Submit commercial filming request to property management"
                )
                if let placeId = placeId { cache(result, for: placeId) }
                return result
            }
        }

        // Tier 2: Category-based risk scoring
        let typesSet = Set(types.map { $0.lowercased() })

        // Check for restricted types first
        if !typesSet.isDisjoint(with: restrictedTypes) {
            let matchedType = typesSet.intersection(restrictedTypes).first ?? "unknown"
            let result = RecordingPolicyResult(
                risk: .restricted,
                reason: "Venue type (\(matchedType)) typically prohibits recording",
                requiresPermission: true,
                suggestedAction: "Recording likely not permitted at this venue type"
            )
            if let placeId = placeId { cache(result, for: placeId) }
            return result
        }

        // Check for caution types (malls, big retail categories)
        if !typesSet.isDisjoint(with: cautionTypes) {
            // Additional check: is this a small independent or a chain?
            // For now, we mark these as caution since we can't determine chain status without name match
            let matchedType = typesSet.intersection(cautionTypes).first ?? "retail"
            let result = RecordingPolicyResult(
                risk: .caution,
                reason: "Retail category (\(matchedType)) often requires permission",
                requiresPermission: false,
                suggestedAction: "Verify with store management before commercial capture"
            )
            if let placeId = placeId { cache(result, for: placeId) }
            return result
        }

        // Check for safe types
        if !typesSet.isDisjoint(with: safeTypes) {
            let result = RecordingPolicyResult.safe
            if let placeId = placeId { cache(result, for: placeId) }
            return result
        }

        // Default: unknown
        return RecordingPolicyResult.unknown
    }

    /// Filters a list of places to only those that are capture-safe
    /// - Parameters:
    ///   - places: Array of place details
    ///   - maxRisk: Maximum acceptable risk level (default: .caution allows safe + unknown + caution)
    /// - Returns: Filtered array of places
    func filterCaptureSafe<T: PlaceWithPolicy>(
        _ places: [T],
        maxRisk: RecordingPolicyRisk = .caution
    ) -> [T] {
        return places.filter { place in
            let policy = evaluatePolicy(
                name: place.policyName,
                types: place.policyTypes,
                placeId: place.policyPlaceId
            )
            return policy.risk <= maxRisk
        }
    }

    /// Checks if a specific place is capture-safe
    func isCaptureSafe(name: String, types: [String], placeId: String? = nil, maxRisk: RecordingPolicyRisk = .caution) -> Bool {
        let policy = evaluatePolicy(name: name, types: types, placeId: placeId)
        return policy.risk <= maxRisk
    }

    /// Returns places sorted by capture safety (safest first)
    func sortByCaptureSafety<T: PlaceWithPolicy>(_ places: [T]) -> [T] {
        return places.sorted { lhs, rhs in
            let lhsPolicy = evaluatePolicy(name: lhs.policyName, types: lhs.policyTypes, placeId: lhs.policyPlaceId)
            let rhsPolicy = evaluatePolicy(name: rhs.policyName, types: rhs.policyTypes, placeId: rhs.policyPlaceId)
            return lhsPolicy.risk < rhsPolicy.risk
        }
    }

    // MARK: - Cache Management

    private func cache(_ result: RecordingPolicyResult, for placeId: String) {
        verificationCache[placeId] = result
        saveCache()
    }

    private func loadCache() {
        // Simple in-memory cache for now
        // Could persist to UserDefaults if needed
    }

    private func saveCache() {
        // Simple in-memory cache for now
    }

    /// Clears the verification cache
    func clearCache() {
        verificationCache.removeAll()
    }

    /// Manually override policy for a specific place (e.g., after getting permission)
    func setManualOverride(placeId: String, policy: RecordingPolicyResult) {
        cache(policy, for: placeId)
    }
}

// MARK: - Protocol for places that can be policy-checked

protocol PlaceWithPolicy {
    var policyName: String { get }
    var policyTypes: [String] { get }
    var policyPlaceId: String? { get }
}

// MARK: - Conformances

extension PlaceDetailsLite: PlaceWithPolicy {
    var policyName: String { displayName }
    var policyTypes: [String] { types ?? [] }
    var policyPlaceId: String? { placeId }
}

// MARK: - Filter Mode Enum (for UI)

enum RecordingPolicyFilter: Int, CaseIterable {
    case all = 0           // Show all places
    case excludeRestricted = 1  // Show all except known restricted chains
    case safeOnly = 2      // Show only safe places (no known restrictions)

    var displayName: String {
        switch self {
        case .all: return "All Places"
        case .safeOnly: return "Safe Only"
        case .excludeRestricted: return "Hide Restricted"
        }
    }

    var shortLabel: String {
        switch self {
        case .all: return "All"
        case .safeOnly: return "Safe"
        case .excludeRestricted: return "No Restricted"
        }
    }

    var maxRisk: RecordingPolicyRisk? {
        switch self {
        case .all: return nil
        case .safeOnly: return .safe
        case .excludeRestricted: return .caution
        }
    }
}
