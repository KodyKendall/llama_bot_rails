module LlamaBotRails
    module Tools
        class RailsConsoleTool
            tool_name "rails_console"
            description "Run a Rails console through MCP Tool calling"

            arguments do 
                required(:command).filled(:string).description("The ruby code to run")
            end

            def call(command:)
                # VERY basic, sandbox for real use!
                result = eval(command)
                { result: result.inspect }
            rescue => e
                { error: e.class.name, message: e.message }
            end
        end
    end
end