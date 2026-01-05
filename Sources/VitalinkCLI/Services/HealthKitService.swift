import Foundation
import HealthKit

public actor HealthKitService {
    private let healthStore: HKHealthStore
    
    public init() throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        self.healthStore = HKHealthStore()
    }
    
    public func requestAuthorization(
        toShare: Set<HKSampleType>,
        read: Set<HKObjectType>
    ) async throws {
        try await healthStore.requestAuthorization(toShare: toShare, read: read)
    }
    
    public func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: type)
    }
    
    public func querySteps(
        start: Date,
        end: Date
    ) async throws -> Double {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.typeNotAvailable("stepCount")
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: stepsType, predicate: predicate),
            options: .cumulativeSum
        )
        
        let result = try await descriptor.result(for: healthStore)
        return result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
    }
    
    public func queryHeartRate(
        start: Date,
        end: Date
    ) async throws -> [HeartRateSample] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitError.typeNotAvailable("heartRate")
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: heartRateType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 100
        )
        
        let samples = try await descriptor.result(for: healthStore)
        return samples.map { sample in
            HeartRateSample(
                value: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                date: sample.startDate
            )
        }
    }
    
    public func queryWorkouts(
        start: Date,
        end: Date,
        activityType: HKWorkoutActivityType? = nil
    ) async throws -> [WorkoutSample] {
        var predicates: [NSPredicate] = [
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        ]
        
        if let activityType = activityType {
            predicates.append(HKQuery.predicateForWorkouts(with: activityType))
        }
        
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(compoundPredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 50
        )
        
        let workouts = try await descriptor.result(for: healthStore)
        return workouts.map { workout in
            WorkoutSample(
                activityType: workout.workoutActivityType.name,
                duration: workout.duration,
                totalEnergyBurned: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                totalDistance: workout.totalDistance?.doubleValue(for: .meter()),
                startDate: workout.startDate,
                endDate: workout.endDate
            )
        }
    }
    
    public func queryQuantity(
        identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date,
        unit: HKUnit
    ) async throws -> [QuantitySample] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.typeNotAvailable(identifier.rawValue)
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: quantityType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 100
        )
        
        let samples = try await descriptor.result(for: healthStore)
        return samples.map { sample in
            QuantitySample(
                value: sample.quantity.doubleValue(for: unit),
                unit: unit.unitString,
                date: sample.startDate
            )
        }
    }
    
    public func queryStatistics(
        identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date,
        options: HKStatisticsOptions
    ) async throws -> StatisticsResult {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.typeNotAvailable(identifier.rawValue)
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: quantityType, predicate: predicate),
            options: options
        )
        
        let result = try await descriptor.result(for: healthStore)
        let unit = unitFor(identifier: identifier)
        
        return StatisticsResult(
            sum: result?.sumQuantity()?.doubleValue(for: unit),
            average: result?.averageQuantity()?.doubleValue(for: unit),
            minimum: result?.minimumQuantity()?.doubleValue(for: unit),
            maximum: result?.maximumQuantity()?.doubleValue(for: unit),
            mostRecent: result?.mostRecentQuantity()?.doubleValue(for: unit),
            unit: unit.unitString
        )
    }
    
    public func saveQuantitySample(
        identifier: HKQuantityTypeIdentifier,
        value: Double,
        unit: HKUnit,
        date: Date
    ) async throws {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.typeNotAvailable(identifier.rawValue)
        }
        
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: quantityType, quantity: quantity, start: date, end: date)
        
        try await healthStore.save(sample)
    }
    
    public func saveWorkout(
        activityType: HKWorkoutActivityType,
        start: Date,
        end: Date,
        totalEnergyBurned: Double?,
        totalDistance: Double?
    ) async throws {
        var energyQuantity: HKQuantity?
        var distanceQuantity: HKQuantity?
        
        if let energy = totalEnergyBurned {
            energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: energy)
        }
        if let distance = totalDistance {
            distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distance)
        }
        
        let workout = HKWorkout(
            activityType: activityType,
            start: start,
            end: end,
            duration: end.timeIntervalSince(start),
            totalEnergyBurned: energyQuantity,
            totalDistance: distanceQuantity,
            metadata: nil
        )
        
        try await healthStore.save(workout)
    }
    
    public func getActivitySummary(for date: Date) async throws -> ActivitySummaryResult? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .era], from: date)
        
        let predicate = HKQuery.predicateForActivitySummary(with: components)
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: predicate)
        
        let summaries = try await descriptor.result(for: healthStore)
        guard let summary = summaries.first else { return nil }
        
        return ActivitySummaryResult(
            activeEnergyBurned: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
            activeEnergyBurnedGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
            exerciseTime: summary.appleExerciseTime.doubleValue(for: .minute()),
            exerciseTimeGoal: summary.exerciseTimeGoal?.doubleValue(for: .minute()) ?? 30,
            standHours: summary.appleStandHours.doubleValue(for: .count()),
            standHoursGoal: summary.standHoursGoal?.doubleValue(for: .count()) ?? 12
        )
    }
    
    private func unitFor(identifier: HKQuantityTypeIdentifier) -> HKUnit {
        switch identifier {
        case .stepCount:
            return .count()
        case .heartRate:
            return HKUnit.count().unitDivided(by: .minute())
        case .activeEnergyBurned, .basalEnergyBurned:
            return .kilocalorie()
        case .distanceWalkingRunning, .distanceCycling:
            return .meter()
        case .bodyMass:
            return .gramUnit(with: .kilo)
        case .height:
            return .meterUnit(with: .centi)
        case .bodyTemperature:
            return .degreeCelsius()
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            return .millimeterOfMercury()
        case .bloodGlucose:
            return HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case .oxygenSaturation:
            return .percent()
        case .respiratoryRate:
            return HKUnit.count().unitDivided(by: .minute())
        default:
            return .count()
        }
    }
}

public enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case typeNotAvailable(String)
    case unauthorized
    case queryFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .typeNotAvailable(let type):
            return "Health data type '\(type)' is not available"
        case .unauthorized:
            return "Not authorized to access health data"
        case .queryFailed(let reason):
            return "Query failed: \(reason)"
        }
    }
}

public struct HeartRateSample: Codable, Sendable {
    public let value: Double
    public let date: Date
}

public struct WorkoutSample: Codable, Sendable {
    public let activityType: String
    public let duration: TimeInterval
    public let totalEnergyBurned: Double?
    public let totalDistance: Double?
    public let startDate: Date
    public let endDate: Date
}

public struct QuantitySample: Codable, Sendable {
    public let value: Double
    public let unit: String
    public let date: Date
}

public struct StatisticsResult: Codable, Sendable {
    public let sum: Double?
    public let average: Double?
    public let minimum: Double?
    public let maximum: Double?
    public let mostRecent: Double?
    public let unit: String
}

public struct ActivitySummaryResult: Codable, Sendable {
    public let activeEnergyBurned: Double
    public let activeEnergyBurnedGoal: Double
    public let exerciseTime: Double
    public let exerciseTimeGoal: Double
    public let standHours: Double
    public let standHoursGoal: Double
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "running"
        case .cycling: return "cycling"
        case .walking: return "walking"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .functionalStrengthTraining: return "strength_training"
        case .traditionalStrengthTraining: return "weight_training"
        case .highIntensityIntervalTraining: return "hiit"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .stairClimbing: return "stair_climbing"
        case .crossTraining: return "cross_training"
        case .mixedCardio: return "mixed_cardio"
        case .coreTraining: return "core_training"
        case .flexibility: return "flexibility"
        case .dance: return "dance"
        case .cooldown: return "cooldown"
        case .other: return "other"
        default: return "unknown"
        }
    }
    
    public static func from(string: String) -> HKWorkoutActivityType? {
        switch string.lowercased() {
        case "running": return .running
        case "cycling": return .cycling
        case "walking": return .walking
        case "swimming": return .swimming
        case "hiking": return .hiking
        case "yoga": return .yoga
        case "strength_training": return .functionalStrengthTraining
        case "weight_training": return .traditionalStrengthTraining
        case "hiit": return .highIntensityIntervalTraining
        case "elliptical": return .elliptical
        case "rowing": return .rowing
        case "stair_climbing": return .stairClimbing
        case "cross_training": return .crossTraining
        case "mixed_cardio": return .mixedCardio
        case "core_training": return .coreTraining
        case "flexibility": return .flexibility
        case "dance": return .dance
        case "cooldown": return .cooldown
        case "other": return .other
        default: return nil
        }
    }
}
