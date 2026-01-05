import Foundation
import HealthKit

public enum HealthDataType: String, CaseIterable, Sendable {
    case steps
    case heartRate = "heart_rate"
    case activeEnergy = "active_energy"
    case basalEnergy = "basal_energy"
    case distance
    case weight
    case height
    case bodyTemperature = "body_temperature"
    case bloodPressureSystolic = "blood_pressure_systolic"
    case bloodPressureDiastolic = "blood_pressure_diastolic"
    case bloodGlucose = "blood_glucose"
    case oxygenSaturation = "oxygen_saturation"
    case respiratoryRate = "respiratory_rate"
    case sleepAnalysis = "sleep"
    case workouts
    case activitySummary = "activity_summary"
    
    public var quantityTypeIdentifier: HKQuantityTypeIdentifier? {
        switch self {
        case .steps: return .stepCount
        case .heartRate: return .heartRate
        case .activeEnergy: return .activeEnergyBurned
        case .basalEnergy: return .basalEnergyBurned
        case .distance: return .distanceWalkingRunning
        case .weight: return .bodyMass
        case .height: return .height
        case .bodyTemperature: return .bodyTemperature
        case .bloodPressureSystolic: return .bloodPressureSystolic
        case .bloodPressureDiastolic: return .bloodPressureDiastolic
        case .bloodGlucose: return .bloodGlucose
        case .oxygenSaturation: return .oxygenSaturation
        case .respiratoryRate: return .respiratoryRate
        case .sleepAnalysis, .workouts, .activitySummary: return nil
        }
    }
    
    public var defaultUnit: HKUnit? {
        switch self {
        case .steps: return .count()
        case .heartRate: return HKUnit.count().unitDivided(by: .minute())
        case .activeEnergy, .basalEnergy: return .kilocalorie()
        case .distance: return .meter()
        case .weight: return .gramUnit(with: .kilo)
        case .height: return .meterUnit(with: .centi)
        case .bodyTemperature: return .degreeCelsius()
        case .bloodPressureSystolic, .bloodPressureDiastolic: return .millimeterOfMercury()
        case .bloodGlucose: return HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case .oxygenSaturation: return .percent()
        case .respiratoryRate: return HKUnit.count().unitDivided(by: .minute())
        case .sleepAnalysis, .workouts, .activitySummary: return nil
        }
    }
    
    public var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .heartRate: return "Heart Rate"
        case .activeEnergy: return "Active Energy"
        case .basalEnergy: return "Basal Energy"
        case .distance: return "Distance"
        case .weight: return "Weight"
        case .height: return "Height"
        case .bodyTemperature: return "Body Temperature"
        case .bloodPressureSystolic: return "Blood Pressure (Systolic)"
        case .bloodPressureDiastolic: return "Blood Pressure (Diastolic)"
        case .bloodGlucose: return "Blood Glucose"
        case .oxygenSaturation: return "Oxygen Saturation"
        case .respiratoryRate: return "Respiratory Rate"
        case .sleepAnalysis: return "Sleep Analysis"
        case .workouts: return "Workouts"
        case .activitySummary: return "Activity Summary"
        }
    }
    
    public static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for dataType in Self.allCases {
            if let identifier = dataType.quantityTypeIdentifier,
               let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        types.insert(HKObjectType.workoutType())
        types.insert(HKObjectType.activitySummaryType())
        return types
    }
    
    public static var shareTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        for dataType in Self.allCases {
            if let identifier = dataType.quantityTypeIdentifier,
               let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        types.insert(HKObjectType.workoutType())
        return types
    }
}
