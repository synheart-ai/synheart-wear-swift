import Foundation

/// Manages user consent for data access and processing
class ConsentManager {
    private let userDefaults = UserDefaults.standard
    private let consentKeyPrefix = "synheart_consent_"

    func initialize() async throws {
        // Initialize consent tracking
    }

    /// Validate that required consents are granted
    func validateConsents(_ permissions: Set<PermissionType>) throws {
        for permission in permissions {
            let key = consentKeyPrefix + permission.rawValue
            guard userDefaults.bool(forKey: key) else {
                throw ConsentError.consentRequired(permission)
            }
        }
    }

    /// Grant consent for a permission
    func grantConsent(_ permission: PermissionType) {
        let key = consentKeyPrefix + permission.rawValue
        userDefaults.set(true, forKey: key)
        userDefaults.set(Date().timeIntervalSince1970, forKey: key + "_time")
    }

    /// Revoke consent for a permission
    func revokeConsent(_ permission: PermissionType) {
        let key = consentKeyPrefix + permission.rawValue
        userDefaults.set(false, forKey: key)
    }

    /// Revoke all consents (GDPR compliance)
    func revokeAllConsents() async throws {
        for permission in PermissionType.allCases {
            revokeConsent(permission)
        }
    }

    /// Check if consent is granted
    func hasConsent(_ permission: PermissionType) -> Bool {
        let key = consentKeyPrefix + permission.rawValue
        return userDefaults.bool(forKey: key)
    }
}

/// Errors related to consent management
enum ConsentError: LocalizedError {
    case consentRequired(PermissionType)

    var errorDescription: String? {
        switch self {
        case .consentRequired(let permission):
            return "Consent required for \(permission)"
        }
    }
}

extension PermissionType {
    var rawValue: String {
        switch self {
        case .heartRate: return "heart_rate"
        case .hrv: return "hrv"
        case .steps: return "steps"
        case .calories: return "calories"
        case .distance: return "distance"
        case .exercise: return "exercise"
        case .sleep: return "sleep"
        case .stress: return "stress"
        }
    }
}
