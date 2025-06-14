require 'llama_bot_rails/llama_bot'
module LlamaBotRails
    class AgentController < ActionController::Base
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

        def threads
            begin
                threads = LlamaBotRails::LlamaBot.get_threads
                render json: threads
            rescue => e
                Rails.logger.error "Error in threads action: #{e.message}"
                render json: { error: "Failed to fetch threads" }, status: :internal_server_error
            end
        end

        def chat_history
            begin
                thread_id = params[:thread_id]
                Rails.logger.info "Fetching chat history for thread: #{thread_id}"
                
                if thread_id == 'undefined' || thread_id.blank?
                    render json: []
                    return
                end
                
                history = LlamaBotRails::LlamaBot.get_chat_history(thread_id)
                render json: history
            rescue => e
                Rails.logger.error "Error in chat_history action: #{e.message}"
                render json: { error: "Failed to fetch chat history" }, status: :internal_server_error
            end
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
            expected_token = ENV["LLAMABOT_AGENT_TOKEN"] || Rails.application.credentials.llamabot_agent_token
            raise "LLAMABOT_AGENT_TOKEN is missing—set ENV or credentials" if expected_token.blank?

            request_token = request.headers["Authorization"]&.split("Bearer ")&.last

            if expected_token.blank? || request_token != expected_token
                render json: { error: "Unauthorized" }, status: :unauthorized
            end
        end
    end
end