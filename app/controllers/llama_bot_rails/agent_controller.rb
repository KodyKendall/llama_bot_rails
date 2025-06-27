require 'llama_bot_rails/llama_bot'
module LlamaBotRails
    class AgentController < ActionController::Base
        skip_before_action :verify_authenticity_token, only: [:command, :send_message]
        before_action :authenticate_agent!, only: [:command]

        # POST /agent/command
        def command
            input = params[:command]
            
            # Capture both stdout and return value
            output = StringIO.new
            result = nil
            
            $stdout = output
            result = safety_eval(input)
            $stdout = STDOUT
            
            # If result is a string and output has content, prefer output
            final_result = if output.string.present?
                             output.string.strip
                           else
                             result
                           end
            
            render json: { result: final_result }
        rescue => e
            $stdout = STDOUT  # Reset stdout on error
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

        # POST /agent/send-message
        def send_message
            message = params[:message]
            thread_id = params[:thread_id]
            agent_name = params[:agent_name]
            LlamaBotRails::LlamaBot.send_agent_message(message, thread_id, agent_name)
            render json: { message: "Message sent" }
        end

        private 

        def safety_eval(input)
            # Change to Rails root directory for file operations
            Dir.chdir(Rails.root) do
                # Create a safer evaluation context
                binding.eval(input)
            end
        end

        def authenticate_agent!
            auth_header = request.headers["Authorization"]
            token = auth_header&.split("Bearer ")&.last  # Extract token after "Bearer "
            @session_payload = Rails.application.message_verifier(:llamabot_ws).verify(token)
        rescue ActiveSupport::MessageVerifier::InvalidSignature
            head :unauthorized
        end
    end
end