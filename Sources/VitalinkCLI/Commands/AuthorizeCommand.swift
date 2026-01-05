import ArgumentParser
import Foundation
import HealthKit

public struct Authorize: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Request authorization to access HealthKit data"
    )
    
    @OptionGroup var options: GlobalOptions
    
    @Option(name: .long, parsing: .upToNextOption, help: "Specific data types to request (default: all)")
    var types: [String] = []
    
    @Flag(name: .long, help: "Request read-only access")
    var readOnly: Bool = false
    
    public init() {}
    
    public func run() async throws {
        let service = try HealthKitService()
        
        let readTypes: Set<HKObjectType>
        let shareTypes: Set<HKSampleType>
        
        if types.isEmpty {
            readTypes = HealthDataType.readTypes
            shareTypes = readOnly ? [] : HealthDataType.shareTypes
        } else {
            var read = Set<HKObjectType>()
            var share = Set<HKSampleType>()
            
            for typeName in types {
                guard let dataType = HealthDataType(rawValue: typeName) else {
                    throw ValidationError("Unknown data type: \(typeName)")
                }
                if let identifier = dataType.quantityTypeIdentifier,
                   let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                    read.insert(type)
                    if !readOnly {
                        share.insert(type)
                    }
                }
            }
            readTypes = read
            shareTypes = share
        }
        
        try await service.requestAuthorization(toShare: shareTypes, read: readTypes)
        
        if options.json {
            let result = AuthorizationResult(
                success: true,
                readTypes: readTypes.map { $0.identifier },
                writeTypes: shareTypes.map { $0.identifier }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Authorization requested successfully")
            print("Read types: \(readTypes.count)")
            print("Write types: \(shareTypes.count)")
        }
    }
}

struct AuthorizationResult: Codable {
    let success: Bool
    let readTypes: [String]
    let writeTypes: [String]
}
