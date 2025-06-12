module LlamaBotRails
    class AgentController < ApplicationController
        protect_from_forgery with: :null_session
        # before_action :authenticate_agent! #TODO: Figure out how we'll authenticate the agent

        # POST /agent/command
        def command
            input = params[:command]
            result = eval(input)
            render json: { result: result.inspect }
        rescue => e
            render json: { error: e.class.name, message: e.message }, status: :unprocessable_entity
        end

        def index
            @llama_bot = LlamaBot.new
        end

        # GET /agent/chat
        def chat
            # Render chat.html.erb
        end

        private 

        def safety_eval(input)
            # VERY basic, sandbox for real use!
            result = eval(input)
            
            { result: result.inspect }
        rescue => e
            { error: e.class.name, message: e.message }
        end

        def authenticate_agent!
            expected_token = ENV["LLAMABOT_AGENT_TOKEN"]
            request_token = request.headers["Authorization"]&.split("Bearer ")&.last

            if expected_token.blank? || request_token != expected_token
                render json: { error: "Unauthorized" }, status: :unauthorized
            end
        end
    end
end