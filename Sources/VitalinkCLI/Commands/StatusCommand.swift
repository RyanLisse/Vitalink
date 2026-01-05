import ArgumentParser
import Foundation
import HealthKit

public struct Status: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Check HealthKit availability and authorization status"
    )
    
    @OptionGroup var options: GlobalOptions
    
    public init() {}
    
    public func run() async throws {
        let available = HKHealthStore.isHealthDataAvailable()
        
        var authStatuses: [String: String] = [:]
        
        if available {
            let healthStore = HKHealthStore()
            
            for dataType in HealthDataType.allCases {
                if let identifier = dataType.quantityTypeIdentifier,
                   let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                    let status = healthStore.authorizationStatus(for: type)
                    authStatuses[dataType.rawValue] = status.description
                }
            }
            
            if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
                authStatuses["sleep"] = healthStore.authorizationStatus(for: sleepType).description
            }
            
            authStatuses["workouts"] = healthStore.authorizationStatus(for: HKObjectType.workoutType()).description
        }
        
        if options.json {
            let result = StatusResult(
                healthKitAvailable: available,
                authorizationStatuses: authStatuses
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Vitalink Status")
            print("===============")
            print("HealthKit Available: \(available ? "Yes" : "No")")
            
            if available {
                print("\nAuthorization Status:")
                for (type, status) in authStatuses.sorted(by: { $0.key < $1.key }) {
                    let icon = status == "sharingAuthorized" ? "+" : (status == "sharingDenied" ? "x" : "?")
                    print("  [\(icon)] \(type): \(status)")
                }
                print("\nLegend: [+] authorized, [x] denied, [?] not determined")
                print("\nRun 'vitalink authorize' to request access to health data.")
            } else {
                print("\nHealthKit is not available on this device.")
                print("Note: HealthKit requires macOS 13+ and may not be available in all configurations.")
            }
        }
    }
}

struct StatusResult: Codable {
    let healthKitAvailable: Bool
    let authorizationStatuses: [String: String]
}

extension HKAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .sharingDenied: return "sharingDenied"
        case .sharingAuthorized: return "sharingAuthorized"
        @unknown default: return "unknown"
        }
    }
}
