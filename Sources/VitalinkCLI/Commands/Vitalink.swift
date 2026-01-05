import ArgumentParser
import Foundation

@available(macOS 14.0, *)
public struct Vitalink: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "vitalink",
        abstract: "A macOS CLI & MCP server for Apple HealthKit - enabling AI agents to read and write health data",
        version: "1.0.0",
        subcommands: [
            Authorize.self,
            Read.self,
            Write.self,
            Query.self,
            MCP.self,
            Status.self,
        ],
        defaultSubcommand: Status.self
    )
    
    public init() {}
}

public struct GlobalOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Output in JSON format")
    public var json: Bool = false
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    public var verbose: Bool = false
    
    public init() {}
}
