require 'llama_bot_rails/llama_bot'
module LlamaBotRails
    class AgentController < ActionController::Base
        include ActionController::Live
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

        # GET /agent/chat_ws
        def chat_ws
            # render chat_ws.html.erb
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
            response.headers['Content-Type']  = 'text/event-stream'
            response.headers['Cache-Control'] = 'no-cache'
            response.headers['Connection']    = 'keep-alive'

            @api_token = Rails.application.message_verifier(:llamabot_ws).generate(
                { session_id: SecureRandom.uuid },
                expires_in: 30.minutes
              )

            # 1. Instantiate the builder
            builder = state_builder_class.new(
                params: params,
                context: { api_token: @api_token }
            )
    
            # 2. Construct the LangGraph-ready state
            state_payload = builder.build
            # sse = SSE.new(response.stream)

            begin
                LlamaBotRails::LlamaBot.send_agent_message(state_payload) do |chunk|
                    Rails.logger.info "[[LlamaBot]] Received chunk in agent_controller.rb: #{chunk}"
                    # sse.write(chunk)
                    response.stream.write "data: #{chunk.to_json}\n\n"

                end
            rescue => e
                Rails.logger.error "Error in send_message action: #{e.message}"
                response.stream.write "data: #{ { type: 'error', content: e.message }.to_json }\n\n"

                # sse.write({ type: 'error', content: e.message })
            ensure
                response.stream.close

                # sse.close
            end
        end

        def test_streaming
            response.headers['Content-Type']  = 'text/event-stream'
            response.headers['Cache-Control'] = 'no-cache'
            response.headers['Connection']    = 'keep-alive'
            sse = SSE.new(response.stream)
            sse.write({ type: 'start', content: 'Starting streaming' })
            sleep 1
            sse.write({ type: 'ai', content: 'This is an AI message' })
            sleep 1
            sse.write({ type: 'ai', content: 'This is an AI message' })
            sleep 1
            sse.write({ type: 'ai', content: 'This is an AI message' })
            sleep 1
            sse.write({ type: 'ai', content: 'This is an AI message' })
        end

        private 

        def safety_eval(input)
            begin
                # Change to Rails root directory for file operations
                Dir.chdir(Rails.root) do
                    # Create a safer evaluation context
                    Rails.logger.info "[[LlamaBot]] Evaluating input: #{input}"
                    binding.eval(input)
                end
            rescue => exception
                Rails.logger.error "Error in safety_eval: #{exception.message}"
                return exception.message
            end
        end

        def authenticate_agent!
            auth_header = request.headers["Authorization"]
            token = auth_header&.split("Bearer ")&.last  # Extract token after "Bearer "
            @session_payload = Rails.application.message_verifier(:llamabot_ws).verify(token)
        rescue ActiveSupport::MessageVerifier::InvalidSignature
            head :unauthorized
        end

        def state_builder_class
            #The user is responsible for creating a custom AgentStateBuilder if they want to use a custom agent. Otherwise, we default to LlamaBotRails::AgentStateBuilder.
            LlamaBotRails.config.state_builder_class.constantize
        end
    end
end