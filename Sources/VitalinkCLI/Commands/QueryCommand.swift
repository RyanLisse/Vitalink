import ArgumentParser
import Foundation
import HealthKit

public struct Query: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Query health data with statistics and aggregations",
        subcommands: [
            QueryStats.self,
            QueryTrends.self,
        ]
    )
    
    public init() {}
}

struct QueryStats: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Get statistics for a data type (min, max, avg, sum)"
    )
    
    @OptionGroup var options: GlobalOptions
    
    @Argument(help: "Data type to query")
    var dataType: String
    
    @Option(name: .long, help: "Start date")
    var from: String = "7d"
    
    @Option(name: .long, help: "End date")
    var to: String = "now"
    
    func run() async throws {
        guard let type = HealthDataType(rawValue: dataType),
              let identifier = type.quantityTypeIdentifier else {
            throw ValidationError("Unknown or unsupported data type: \(dataType)")
        }
        
        let service = try HealthKitService()
        let (start, end) = try parseDateRange(from: from, to: to)
        
        var statsOptions: HKStatisticsOptions = []
        switch identifier {
        case .stepCount, .activeEnergyBurned, .basalEnergyBurned, .distanceWalkingRunning, .distanceCycling:
            statsOptions = [.cumulativeSum]
        default:
            statsOptions = [.discreteAverage, .discreteMin, .discreteMax, .mostRecent]
        }
        
        let result = try await service.queryStatistics(
            identifier: identifier,
            start: start,
            end: end,
            options: statsOptions
        )
        
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("\(type.displayName) Statistics (\(start.formatted()) to \(end.formatted()))")
            if let sum = result.sum {
                print("  Total: \(formatValue(sum, for: type)) \(result.unit)")
            }
            if let avg = result.average {
                print("  Average: \(formatValue(avg, for: type)) \(result.unit)")
            }
            if let min = result.minimum {
                print("  Minimum: \(formatValue(min, for: type)) \(result.unit)")
            }
            if let max = result.maximum {
                print("  Maximum: \(formatValue(max, for: type)) \(result.unit)")
            }
            if let recent = result.mostRecent {
                print("  Most Recent: \(formatValue(recent, for: type)) \(result.unit)")
            }
        }
    }
    
    func formatValue(_ value: Double, for type: HealthDataType) -> String {
        switch type {
        case .steps:
            return String(Int(value))
        case .heartRate, .respiratoryRate:
            return String(format: "%.0f", value)
        case .weight:
            return String(format: "%.1f", value)
        case .oxygenSaturation:
            return String(format: "%.1f%%", value * 100)
        default:
            return String(format: "%.2f", value)
        }
    }
}

struct QueryTrends: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trends",
        abstract: "Get daily/weekly/monthly trends for a data type"
    )
    
    @OptionGroup var options: GlobalOptions
    
    @Argument(help: "Data type to analyze")
    var dataType: String
    
    @Option(name: .long, help: "Start date")
    var from: String = "30d"
    
    @Option(name: .long, help: "End date")
    var to: String = "now"
    
    @Option(name: .long, help: "Grouping interval: day, week, month")
    var interval: String = "day"
    
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
        
        let calendar = Calendar.current
        let groupedData: [String: [Double]]
        
        switch interval.lowercased() {
        case "day":
            groupedData = Dictionary(grouping: samples) { sample in
                let components = calendar.dateComponents([.year, .month, .day], from: sample.date)
                return "\(components.year!)-\(String(format: "%02d", components.month!))-\(String(format: "%02d", components.day!))"
            }.mapValues { $0.map(\.value) }
        case "week":
            groupedData = Dictionary(grouping: samples) { sample in
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: sample.date)
                return "\(components.yearForWeekOfYear!)-W\(String(format: "%02d", components.weekOfYear!))"
            }.mapValues { $0.map(\.value) }
        case "month":
            groupedData = Dictionary(grouping: samples) { sample in
                let components = calendar.dateComponents([.year, .month], from: sample.date)
                return "\(components.year!)-\(String(format: "%02d", components.month!))"
            }.mapValues { $0.map(\.value) }
        default:
            throw ValidationError("Invalid interval: \(interval). Use: day, week, month")
        }
        
        var trends: [TrendEntry] = []
        for (period, values) in groupedData.sorted(by: { $0.key < $1.key }) {
            let avg = values.reduce(0, +) / Double(values.count)
            let sum = values.reduce(0, +)
            trends.append(TrendEntry(
                period: period,
                count: values.count,
                sum: sum,
                average: avg,
                min: values.min() ?? 0,
                max: values.max() ?? 0
            ))
        }
        
        if options.json {
            let result = TrendsResult(
                dataType: dataType,
                interval: interval,
                unit: unit.unitString,
                trends: trends
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("\(type.displayName) Trends by \(interval)")
            for entry in trends {
                print("  \(entry.period): avg=\(String(format: "%.1f", entry.average)), sum=\(String(format: "%.0f", entry.sum)), samples=\(entry.count)")
            }
        }
    }
}

struct TrendEntry: Codable {
    let period: String
    let count: Int
    let sum: Double
    let average: Double
    let min: Double
    let max: Double
}

struct TrendsResult: Codable {
    let dataType: String
    let interval: String
    let unit: String
    let trends: [TrendEntry]
}
