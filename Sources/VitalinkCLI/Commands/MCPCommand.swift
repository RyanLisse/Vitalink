import ArgumentParser
import Foundation

public struct MCP: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Start the MCP (Model Context Protocol) server for AI agents",
        subcommands: [
            Serve.self,
            Tools.self,
        ],
        defaultSubcommand: Serve.self
    )
    
    public init() {}
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start the MCP server"
    )
    
    @Option(name: .long, help: "Transport type: stdio (default)")
    var transport: String = "stdio"
    
    func run() async throws {
        guard transport == "stdio" else {
            throw ValidationError("Only stdio transport is currently supported")
        }
        
        let server = VitalinkMCPServer()
        try await server.run()
    }
}

struct Tools: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tools",
        abstract: "List available MCP tools"
    )
    
    @Flag(name: .shortAndLong, help: "Output in JSON format")
    var json: Bool = false
    
    func run() throws {
        let tools = VitalinkMCPServer.toolDefinitions
        
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(tools)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Available MCP Tools:")
            print("====================")
            for tool in tools {
                print("\n\(tool.name)")
                print("  \(tool.description)")
            }
        }
    }
}
