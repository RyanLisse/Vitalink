import ArgumentParser
import Foundation
import HealthKit

public struct Write: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Write health data to HealthKit",
        subcommands: [
            WriteQuantity.self,
            WriteWorkout.self,
        ]
    )
    
    public init() {}
}

struct WriteQuantity: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quantity",
        abstract: "Write a quantity sample (e.g., weight, blood glucose)"
    )
    
    @OptionGroup var options: GlobalOptions
    
    @Argument(help: "Data type (e.g., weight, height, blood_glucose)")
    var dataType: String
    
    @Argument(help: "Value to record")
    var value: Double
    
    @Option(name: .long, help: "Date/time of measurement (default: now)")
    var date: String = "now"
    
    @Option(name: .long, help: "Override unit (e.g., 'lb' for pounds instead of kg)")
    var unit: String?
    
    func run() async throws {
        guard let type = HealthDataType(rawValue: dataType),
              let identifier = type.quantityTypeIdentifier else {
            throw ValidationError("Unknown or unsupported data type: \(dataType). Writable types: \(HealthDataType.allCases.compactMap { $0.quantityTypeIdentifier != nil ? $0.rawValue : nil }.joined(separator: ", "))")
        }
        
        let hkUnit: HKUnit
        if let unitStr = unit {
            hkUnit = try parseUnit(unitStr, for: type)
        } else {
            guard let defaultUnit = type.defaultUnit else {
                throw ValidationError("No default unit for \(dataType)")
            }
            hkUnit = defaultUnit
        }
        
        let service = try HealthKitService()
        let recordDate = try parseDate(date)
        
        try await service.saveQuantitySample(
            identifier: identifier,
            value: value,
            unit: hkUnit,
            date: recordDate
        )
        
        if options.json {
            let result = WriteResult(
                success: true,
                dataType: dataType,
                value: value,
                unit: hkUnit.unitString,
                date: recordDate
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(result)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Saved \(type.displayName): \(value) \(hkUnit.unitString) at \(recordDate.formatted())")
        }
    }
    
    func parseUnit(_ unitStr: String, for type: HealthDataType) throws -> HKUnit {
        switch unitStr.lowercased() {
        case "kg": return .gramUnit(with: .kilo)
        case "lb", "lbs": return .pound()
        case "g": return .gram()
        case "m": return .meter()
        case "cm": return .meterUnit(with: .centi)
        case "ft": return .foot()
        case "in": return .inch()
        case "c", "celsius": return .degreeCelsius()
        case "f", "fahrenheit": return .degreeFahrenheit()
        case "mmhg": return .millimeterOfMercury()
        case "mg/dl": return HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case "mmol/l": return HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())
        case "%", "percent": return .percent()
        case "count": return .count()
        case "kcal": return .kilocalorie()
        case "cal": return .smallCalorie()
        default:
            throw ValidationError("Unknown unit: \(unitStr)")
        }
    }
}

struct WriteWorkout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workout",
        abstract: "Record a workout"
    )
    
    @OptionGroup var options: GlobalOptions
    
    @Argument(help: "Activity type (e.g., running, cycling, swimming, yoga)")
    var activityType: String
    
    @Option(name: .long, help: "Workout start time")
    var start: String
    
    @Option(name: .long, help: "Workout end time (default: now)")
    var end: String = "now"
    
    @Option(name: .long, help: "Total calories burned (kcal)")
    var calories: Double?
    
    @Option(name: .long, help: "Total distance (meters)")
    var distance: Double?
    
    func run() async throws {
        guard let workoutType = HKWorkoutActivityType.from(string: activityType) else {
            throw ValidationError("Unknown activity type: \(activityType). Valid types: running, cycling, walking, swimming, hiking, yoga, strength_training, weight_training, hiit, elliptical, rowing, stair_climbing, cross_training, mixed_cardio, core_training, flexibility, dance, cooldown, other")
        }
        
        let service = try HealthKitService()
        let startDate = try parseDate(start)
        let endDate = try parseDate(end)
        
        guard endDate > startDate else {
            throw ValidationError("End time must be after start time")
        }
        
        try await service.saveWorkout(
            activityType: workoutType,
            start: startDate,
            end: endDate,
            totalEnergyBurned: calories,
            totalDistance: distance
        )
        
        if options.json {
            let result = WorkoutWriteResult(
                success: true,
                activityType: activityType,
                startDate: startDate,
                endDate: endDate,
                duration: endDate.timeIntervalSince(startDate),
                calories: calories,
                distance: distance
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(result)
            print(String(data: data, encoding: .utf8)!)
        } else {
            let duration = Int(endDate.timeIntervalSince(startDate) / 60)
            print("Saved workout: \(activityType)")
            print("  Duration: \(duration) minutes")
            if let cal = calories {
                print("  Calories: \(Int(cal)) kcal")
            }
            if let dist = distance {
                print("  Distance: \(String(format: "%.2f", dist / 1000)) km")
            }
        }
    }
}

struct WriteResult: Codable {
    let success: Bool
    let dataType: String
    let value: Double
    let unit: String
    let date: Date
}

struct WorkoutWriteResult: Codable {
    let success: Bool
    let activityType: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let calories: Double?
    let distance: Double?
}
