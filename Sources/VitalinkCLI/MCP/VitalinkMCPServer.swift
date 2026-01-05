import Foundation
import MCP
import HealthKit

public actor VitalinkMCPServer {
    private var server: Server?
    private var healthService: HealthKitService?
    
    public init() {}
    
    public func run() async throws {
        let transport = StdioTransport()
        
        let capabilities = Server.Capabilities(
            tools: .init(listChanged: false)
        )
        
        let server = Server(
            name: "vitalink",
            version: "1.0.0",
            capabilities: capabilities
        )
        self.server = server
        
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: Self.mcpTools)
        }
        
        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self = self else {
                throw VitalinkMCPError.internalError("Server not initialized")
            }
            return try await self.handleToolCall(params)
        }
        
        do {
            healthService = try HealthKitService()
        } catch {
            FileHandle.standardError.write("Warning: HealthKit not available - \(error.localizedDescription)\n".data(using: .utf8)!)
        }
        
        try await server.start(transport: transport)
    }
    
    private func handleToolCall(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let toolName = params.name
        let args = params.arguments ?? [:]
        
        switch toolName {
        case "health_status":
            return try await handleStatus()
            
        case "health_authorize":
            return try await handleAuthorize(args)
            
        case "health_read_steps":
            return try await handleReadSteps(args)
            
        case "health_read_heart_rate":
            return try await handleReadHeartRate(args)
            
        case "health_read_workouts":
            return try await handleReadWorkouts(args)
            
        case "health_read_activity":
            return try await handleReadActivity(args)
            
        case "health_read_quantity":
            return try await handleReadQuantity(args)
            
        case "health_query_stats":
            return try await handleQueryStats(args)
            
        case "health_write_quantity":
            return try await handleWriteQuantity(args)
            
        case "health_write_workout":
            return try await handleWriteWorkout(args)
            
        default:
            throw VitalinkMCPError.methodNotFound("Unknown tool: \(toolName)")
        }
    }
    
    private func handleStatus() async throws -> CallTool.Result {
        let available = HKHealthStore.isHealthDataAvailable()
        return CallTool.Result(content: [.text("{\"healthKitAvailable\": \(available)}")])
    }
    
    private func handleAuthorize(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let service = healthService else {
            throw VitalinkMCPError.internalError("HealthKit not available")
        }
        
        try await service.requestAuthorization(
            toShare: HealthDataType.shareTypes,
            read: HealthDataType.readTypes
        )
        
        return CallTool.Result(content: [.text("{\"success\": true}")])
    }
    
    private func handleReadSteps(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let service = healthService else {
            throw VitalinkMCPError.internalError("HealthKit not available")
        }
        
        let (start, end) = try parseDateArgs(args)
        let steps = try await service.querySteps(start: start, end: end)
        
        let result = StepsResult(steps: steps, startDate: start, endDate: end)
        return CallTool.Result(content: [.text(toJSONCodable(result))])
    }
    
    private func handleReadHeartRate(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let service = healthService else {
            throw VitalinkMCPError.internalError("HealthKit not available")
        }
        
        let (start, end) = try parseDateArgs(args)
        let samples = try await service.queryHeartRate(start: start, end: end)
        
        return CallTool.Result(content: [.text(toJSONCodable(samples))])
    }
    
    private func handleReadWorkouts(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let service = healthService else {
            throw VitalinkMCPError.internalError("HealthKit not available")
        }
        
        let (start, end) = try parseDateArgs(args, defaultFrom: "30d")
        
        var activityType: HKWorkoutActivityType?
        if case .string(let typeStr) = args["activity_type"] {
            activityType = HKWorkoutActivityType.from(string: typeStr)
        }
        
        let workouts = try await service.queryWorkouts(
            start: start,
            end: end,
            activityType: activityType
        )
        
        return CallTool.Result(content: [.text(toJSONCodable(workouts))])
    }
    
    private func handleReadActivity(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let service = healthService else {
            throw VitalinkMCPError.internalError("HealthKit not available")
        }
        
        let targetDate: Date
        if case .string(let dateStr) = args["date"] {
            targetDate = try parseDate(dateStr)
        } else {
            targetDate = Date()
        }
        
        guard let summary = try await service.getActivitySummary(for: targetDate) else {
            return CallTool.Result(content: [.text("{\"error\": \"No activity summary for this date\"}")])
        }
        
        return CallTool.Result(content: [.text(toJSONCodable(summary))])
    }
    
    private func handleReadQuantity(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let service = healthService else {
            throw VitalinkMCPError.internalError("HealthKit not available")
        }
        
        guard case .string(let dataTypeStr) = args["data_type"],
              let dataType = HealthDataType(rawValue: dataTypeStr),
              let identifier = dataType.quantityTypeIdentifier,
              let unit = dataType.defaultUnit else {
            throw VitalinkMCPError.invalidParams("Missing or invalid data_type parameter")
        }
        
        let (start, end) = try parseDateArgs(args)
        let samples = try await service.queryQuantity(
            identifier: identifier,
            start: start,
            end: end,
            unit: unit
        )
        
        return CallTool.Result(content: [.text(toJSONCodable(samples))])
    }
    
    private func handleQueryStats(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let service = healthService else {
            throw VitalinkMCPError.internalError("HealthKit not available")
        }
        
        guard case .string(let dataTypeStr) = args["data_type"],
              let dataType = HealthDataType(rawValue: dataTypeStr),
              let identifier = dataType.quantityTypeIdentifier else {
            throw VitalinkMCPError.invalidParams("Missing or invalid data_type parameter")
        }
        
        let (start, end) = try parseDateArgs(args)
        
        var statsOptions: HKStatisticsOptions = []
        switch identifier {
        case .stepCount, .activeEnergyBurned, .basalEnergyBurned, .distanceWalkingRunning:
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
        
        return CallTool.Result(content: [.text(toJSONCodable(result))])
    }
    
    private func handleWriteQuantity(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let service = healthService else {
            throw VitalinkMCPError.internalError("HealthKit not available")
        }
        
        guard case .string(let dataTypeStr) = args["data_type"],
              let dataType = HealthDataType(rawValue: dataTypeStr),
              let identifier = dataType.quantityTypeIdentifier,
              let unit = dataType.defaultUnit else {
            throw VitalinkMCPError.invalidParams("Missing or invalid data_type parameter")
        }
        
        let value = extractNumber(from: args["value"])
        guard let value else {
            throw VitalinkMCPError.invalidParams("Missing value parameter")
        }
        
        let recordDate: Date
        if case .string(let dateStr) = args["date"] {
            recordDate = try parseDate(dateStr)
        } else {
            recordDate = Date()
        }
        
        try await service.saveQuantitySample(
            identifier: identifier,
            value: value,
            unit: unit,
            date: recordDate
        )
        
        let result = WriteResult(
            success: true,
            dataType: dataTypeStr,
            value: value,
            unit: unit.unitString,
            date: recordDate
        )
        
        return CallTool.Result(content: [.text(toJSONCodable(result))])
    }
    
    private func handleWriteWorkout(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let service = healthService else {
            throw VitalinkMCPError.internalError("HealthKit not available")
        }
        
        guard case .string(let activityTypeStr) = args["activity_type"],
              let activityType = HKWorkoutActivityType.from(string: activityTypeStr) else {
            throw VitalinkMCPError.invalidParams("Missing or invalid activity_type parameter")
        }
        
        guard case .string(let startStr) = args["start"] else {
            throw VitalinkMCPError.invalidParams("Missing start parameter")
        }
        
        let startDate = try parseDate(startStr)
        let endDate: Date
        if case .string(let endStr) = args["end"] {
            endDate = try parseDate(endStr)
        } else {
            endDate = Date()
        }
        
        let calories = extractNumber(from: args["calories"])
        let distance = extractNumber(from: args["distance"])
        
        try await service.saveWorkout(
            activityType: activityType,
            start: startDate,
            end: endDate,
            totalEnergyBurned: calories,
            totalDistance: distance
        )
        
        let result = WorkoutWriteResult(
            success: true,
            activityType: activityTypeStr,
            startDate: startDate,
            endDate: endDate,
            duration: endDate.timeIntervalSince(startDate),
            calories: calories,
            distance: distance
        )
        
        return CallTool.Result(content: [.text(toJSONCodable(result))])
    }
    
    private func extractNumber(from value: Value?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }
    
    private func parseDateArgs(_ args: [String: Value], defaultFrom: String = "7d") throws -> (Date, Date) {
        let fromStr: String
        if case .string(let str) = args["from"] {
            fromStr = str
        } else {
            fromStr = defaultFrom
        }
        
        let toStr: String
        if case .string(let str) = args["to"] {
            toStr = str
        } else {
            toStr = "now"
        }
        
        return try parseDateRange(from: fromStr, to: toStr)
    }
    
    private func toJSONCodable<T: Codable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

extension VitalinkMCPServer {
    public static let toolDefinitions: [ToolDefinition] = [
        ToolDefinition(
            name: "health_status",
            description: "Check if HealthKit is available on this device"
        ),
        ToolDefinition(
            name: "health_authorize",
            description: "Request authorization to access health data. Must be called before reading or writing data."
        ),
        ToolDefinition(
            name: "health_read_steps",
            description: "Read step count data. Parameters: from (date string, default '7d'), to (date string, default 'now'). Date formats: ISO8601, 'now', 'today', or relative like '7d', '1w', '1m'."
        ),
        ToolDefinition(
            name: "health_read_heart_rate",
            description: "Read heart rate samples. Parameters: from, to (date strings). Returns array of {value, date} samples."
        ),
        ToolDefinition(
            name: "health_read_workouts",
            description: "Read workout data. Parameters: from (default '30d'), to, activity_type (optional, e.g., 'running', 'cycling', 'swimming')."
        ),
        ToolDefinition(
            name: "health_read_activity",
            description: "Read activity summary (Apple Watch rings). Parameters: date (default today). Returns move/exercise/stand goals and progress."
        ),
        ToolDefinition(
            name: "health_read_quantity",
            description: "Read any quantity type. Parameters: data_type (required: steps, heart_rate, weight, height, blood_glucose, etc.), from, to."
        ),
        ToolDefinition(
            name: "health_query_stats",
            description: "Get statistics (sum/avg/min/max) for a data type. Parameters: data_type (required), from, to."
        ),
        ToolDefinition(
            name: "health_write_quantity",
            description: "Write a health measurement. Parameters: data_type (required), value (required), date (default now)."
        ),
        ToolDefinition(
            name: "health_write_workout",
            description: "Record a workout. Parameters: activity_type (required), start (required), end (default now), calories (optional), distance (optional, meters)."
        ),
    ]
    
    static var mcpTools: [Tool] {
        toolDefinitions.map { def in
            Tool(
                name: def.name,
                description: def.description,
                inputSchema: .object([:])
            )
        }
    }
}

public struct ToolDefinition: Codable, Sendable {
    public let name: String
    public let description: String
}

enum VitalinkMCPError: Error, LocalizedError {
    case internalError(String)
    case methodNotFound(String)
    case invalidParams(String)
    
    var errorDescription: String? {
        switch self {
        case .internalError(let msg): return "Internal error: \(msg)"
        case .methodNotFound(let msg): return "Method not found: \(msg)"
        case .invalidParams(let msg): return "Invalid parameters: \(msg)"
        }
    }
}
