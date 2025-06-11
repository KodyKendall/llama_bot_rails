namespace :llama_bot do
    desc "Start the MCP server"
    task :start_mcp => :environment do
        require_relative "../llama_bot_rails/mcp/server"
        LlamaBotRails::MCPServer.start!
    rescue => e
        warn "[MCP ERROR] #{e.class.name}: #{e.message}"
        warn "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
        exit 1
    end
end