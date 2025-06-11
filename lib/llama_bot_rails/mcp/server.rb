require "bundler/setup"
require "fast_mcp"
require_relative "../tools/rails_console_tool"

module LlamaBotRails
    class MCPServer
        def self.start!
            server = FastMcp::Server.new(
                name: "llama-bot-rails",
                version: "0.1.0"
            )

            server.register_tool(LlamaBotRails::Tools::RailsConsoleTool)

            server.start
        end
    end
end

begin
    LlamaBotRails::MCPServer.start! 
rescue => e
    warn "[MCP ERROR] #{e.class.name}: #{e.message}"
    warn "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
    exit 1
end
