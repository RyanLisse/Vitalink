import ArgumentParser
import Foundation
import HealthKit

public struct Read: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Read health data from HealthKit",
        subcommands: [
            ReadSteps.self,
            ReadHeartRate.self,
            ReadWorkouts.self,
            ReadActivity.self,
            ReadQuantity.self,
        ]
    )
    
    public init() {}
}

struct ReadSteps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "steps",
        abstract: "Read step count data"
    )
    
    @OptionGroup var options: GlobalOptions
    
    @Option(name: .long, help: "Start date (ISO8601 or relative like '7d', '1w', '1m')")
    var from: String = "1d"
    
    @Option(name: .long, help: "End date (ISO8601 or 'now')")
    var to: String = "now"
    
    func run() async throws {
        let service = try HealthKitService()
        let (start, end) = try parseDateRange(from: from, to: to)
        
        let steps = try await service.querySteps(start: start, end: end)
        
        if options.json {
            let result = StepsResult(steps: steps, startDate: start, endDate: end)
            print(result.toJSON())
        } else {
            print("Steps from \(start.formatted()) to \(end.formatted())")
            print("Total: \(Int(steps)) steps")
        }
    }
}

struct ReadHeartRate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "heart-rate",
        abstract: "Read heart rate data"
    )
    
    @OptionGroup var options: GlobalOptions
    
    @Option(name: .long, help: "Start date")
    var from: String = "1d"
    
    @Option(name: .long, help: "End date")
    var to: String = "now"
    
    @Option(name: .long, help: "Maximum number of samples")
    var limit: Int = 100
    
    func run() async throws {
        let service = try HealthKitService()
        let (start, end) = try parseDateRange(from: from, to: to)
        
        let samples = try await service.queryHeartRate(start: start, end: end)
        
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(samples)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Heart Rate from \(start.formatted()) to \(end.formatted())")
            print("Samples: \(samples.count)")
            for sample in samples.prefix(10) {
                print("  \(sample.date.formatted()): \(Int(sample.value)) BPM")
            }
            if samples.count > 10 {
                print("  ... and \(samples.count - 10) more")
            }
        }
    }
}

struct ReadWorkouts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workouts",
        abstract: "Read workout data"
    )
    
    @OptionGroup var options: GlobalOptions
    
    @Option(name: .long, help: "Start date")
    var from: String = "30d"
    
    @Option(name: .long, help: "End date")
    var to: String = "now"
    
    @Option(name: .long, help: "Filter by activity type (e.g., running, cycling, swimming)")
    var activityType: String?
    
    func run() async throws {
        let service = try HealthKitService()
        let (start, end) = try parseDateRange(from: from, to: to)
        
        var workoutType: HKWorkoutActivityType?
        if let activityName = activityType {
            workoutType = HKWorkoutActivityType.from(string: activityName)
        }
        
        let workouts = try await service.queryWorkouts(
            start: start,
            end: end,
            activityType: workoutType
        )
        
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(workouts)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Workouts from \(start.formatted()) to \(end.formatted())")
            print("Total: \(workouts.count) workouts")
            for workout in workouts.prefix(10) {
                let duration = Int(workout.duration / 60)
                print("  \(workout.startDate.formatted()): \(workout.activityType) - \(duration) min")
                if let calories = workout.totalEnergyBurned {
                    print("    Energy: \(Int(calories)) kcal")
                }
                if let distance = workout.totalDistance {
                    print("    Distance: \(String(format: "%.2f", distance / 1000)) km")
                }
            }
        }
    }
}

struct ReadActivity: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activity",
        abstract: "Read activity summary (rings)"
    )
    
    @OptionGroup var options: GlobalOptions
    
    @Option(name: .long, help: "Date for activity summary (default: today)")
    var date: String = "today"
    
    func run() async throws {
        let service = try HealthKitService()
        let targetDate = try parseDate(date)
        
        guard let summary = try await service.getActivitySummary(for: targetDate) else {
            if options.json {
                print("{\"error\": \"No activity summary for this date\"}")
            } else {
                print("No activity summary available for \(targetDate.formatted())")
            }
            return
        }
        
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(summary)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Activity Summary for \(targetDate.formatted())")
            print("Move: \(Int(summary.activeEnergyBurned))/\(Int(summary.activeEnergyBurnedGoal)) kcal")
            print("Exercise: \(Int(summary.exerciseTime))/\(Int(summary.exerciseTimeGoal)) min")
            print("Stand: \(Int(summary.standHours))/\(Int(summary.standHoursGoal)) hours")
        }
    }
}

struct ReadQuantity: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quantity",
        abstract: "Read any quantity type data"
    )
    
    @OptionGroup var options: GlobalOptions
    
    @Argument(help: "Data type to read (e.g., weight, height, blood_glucose)")
    var dataType: String
    
    @Option(name: .long, help: "Start date")
    var from: String = "7d"
    
    @Option(name: .long, help: "End date")
    var to: String = "now"
    
    func run() async throws {
        guard let type = HealthDataType(rawValue: dataType),
              let identifier = type.quantityTypeIdentifier,
              let unit = type.defaultUnit else {
            throw ValidationError("Unknown or unsupported data type: \(dataType)")
        }
        
        let service = try HealthKitService()
        let (start, end) = try parseDateRange(from: from, to: to)
        
        let samples = try await service.queryQuantity(
            identifier: identifier,
            start: start,
            end: end,
            unit: unit
        )
        
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(samples)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("\(type.displayName) from \(start.formatted()) to \(end.formatted())")
            print("Samples: \(samples.count)")
            for sample in samples.prefix(10) {
                print("  \(sample.date.formatted()): \(sample.value) \(sample.unit)")
            }
        }
    }
}

struct StepsResult: Codable {
    let steps: Double
    let startDate: Date
    let endDate: Date
    
    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

func parseDateRange(from: String, to: String) throws -> (Date, Date) {
    let start = try parseDate(from)
    let end = try parseDate(to)
    return (start, end)
}

func parseDate(_ string: String) throws -> Date {
    let now = Date()
    let calendar = Calendar.current
    
    switch string.lowercased() {
    case "now":
        return now
    case "today":
        return calendar.startOfDay(for: now)
    default:
        break
    }
    
    let relativePattern = #/^(\d+)([dhwm])$/#
    if let match = string.lowercased().firstMatch(of: relativePattern) {
        let value = Int(match.1)!
        let unit = String(match.2)
        
        var component: Calendar.Component
        switch unit {
        case "d": component = .day
        case "h": component = .hour
        case "w": component = .weekOfYear
        case "m": component = .month
        default:
            throw ValidationError("Invalid relative date unit: \(unit)")
        }
        
        guard let date = calendar.date(byAdding: component, value: -value, to: now) else {
            throw ValidationError("Could not calculate date from: \(string)")
        }
        return date
    }
    
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) {
        return date
    }
    
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: string) {
        return date
    }
    
    formatter.formatOptions = [.withFullDate]
    if let date = formatter.date(from: string) {
        return date
    }
    
    throw ValidationError("Could not parse date: \(string)")
}
