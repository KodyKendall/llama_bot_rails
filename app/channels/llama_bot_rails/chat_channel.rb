require 'json'  # Ensure JSON is required if not already

module LlamaBotRails
  class ChatChannel < ApplicationCable::Channel
    # _chat.html.erb front-end subscribes to this channel in _websocket.html.erb.
    def subscribed
      begin
        stream_from "chat_channel_#{params[:session_id]}" # Public stream for session-based messages <- this is the channel we're subscribing to in _websocket.html.erb
        Rails.logger.info "Subscribed to chat channel with session ID: #{params[:session_id]}"
        
        @connection_id = SecureRandom.uuid
        Rails.logger.info "Created new connection with ID: #{@connection_id}"
        Rails.logger.info "[LlamaBot] Secure API token genereated."

        # Use a begin/rescue block to catch thread creation errors
      begin

        @api_token = Rails.application.message_verifier(:llamabot_ws).generate(
          { session_id: SecureRandom.uuid },
          expires_in: 30.minutes
        )

        @worker = Thread.new do
            Thread.current[:connection_id] = @connection_id
          Thread.current.abort_on_exception = true  # This will help surface errors
          setup_external_websocket(@connection_id)
        end
      rescue => e
        Rails.logger.error "Error in WebSocket subscription: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Send error message to frontend before rejecting
        begin
          send_message_to_frontend("error", "Failed to establish chat connection: #{e.message}")
        rescue => send_error
          Rails.logger.error "Could not send error to frontend: #{send_error.message}"
        end
        
        reject # Reject the connection if there's an error
        end
      rescue ThreadError => e
        Rails.logger.error "Failed to allocate thread: #{e.message}"
        # Handle the error gracefully - potentially notify the client
        send_message_to_frontend("error", "Failed to establish connection: #{e.message}")
      end
    end

    def unsubscribed
      connection_id = @connection_id
      Rails.logger.info "Unsubscribing connection: #{connection_id}"
      
      begin
        # Only kill the worker if it belongs to this connection
        if @worker && @worker[:connection_id] == connection_id
          begin
            @worker.kill
            @worker = nil
            Rails.logger.info "Killed worker thread for connection: #{connection_id}"
          rescue => e
            Rails.logger.error "Error killing worker thread: #{e.message}"
          end
        end

        # Clean up async tasks with better error handling
        begin
          @listener_task&.stop rescue nil
          @keepalive_task&.stop rescue nil
          @external_ws_task&.stop rescue nil
        rescue => e
          Rails.logger.error "Error stopping async tasks: #{e.message}"
        end
        
        # Clean up the connection
        if @external_ws_connection
          begin
            @external_ws_connection.close
            Rails.logger.info "Closed external WebSocket connection for: #{connection_id}"
          rescue => e
            Rails.logger.warn "Could not close WebSocket connection: #{e.message}"
          end
        end
        
        # Force garbage collection in development/test environments to help clean up
        if !Rails.env.production?
          GC.start
        end
      rescue => e
        Rails.logger.error "Fatal error during channel unsubscription: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

    # Receive messages from _chat.html.erb frontend and send to llamabot FastAPI backend, frontend comes from the llamabot/_chat.html.erb chatbot, sent
    # through external websocket to FastAPI/Python backend.
    def receive(data)
      begin
        Rails.logger.info "Message Received from frontend!"

        #used to validate the message before it's sent to the backend.

        #This could be an example of how we might implement hooks & filters in the future.
        validate_message(data) #Placeholder for now, we are using this to mock errors being thrown. In the future, we can add actual validation logic.

        #TODO: Add in hooks & filters here, so that the developer can customize and add their own logic.s
        # Standardize field names so LlamaBot Backend can understand
        # data["web_page_id"] = data["webPageId"]
        # data["user_message"] = data["message"]
        # data["selected_element"] = data["selectedElement"] 
        # data["user_llamapress_api_token"] = current_user.api_token

        #TODO: Add in hooks & filters here, so that the developer can customize and add their own logic.s
        # # Add site's system_prompt to the data if it exists
        # if @web_page&.site&.system_prompt.present?
        #   data["system_prompt"] = @web_page.site.system_prompt
        # end

                #TODO: Add in hooks & filters here, so that the developer can customize and add their own logic.s

        # Add site's llamabot_agent_name to the data if it exists
        # if @web_page&.site&.llamabot_agent_name.present?
        #   data["llamabot_agent_name"] = @web_page.site.llamabot_agent_name # this is so the user can choose the agent they want to use
        # end 
        
        #TODO: Add in hooks & filters here, so that the developer can customize and add their own logic.s
        # if @web_page.site.wordpress_api_encoded_token.present?
        #   data["wordpress_api_encoded_token"] = @web_page.site.wordpress_api_encoded_token
        # else
        #   data["wordpress_api_encoded_token"] = nil
        # end
        
        # Forward the processed data to the LlamaBot Backend Socket
        message = data["message"]

        # 1. Instantiate the builder
        builder = state_builder_class.new(
          params: { message: data["message"] },
          context: { thread_id: data["thread_id"], api_token: @api_token }
        )

        # 2. Construct the LangGraph-ready state
        state_payload = builder.build

        # 3. Ship it over the existing WebSocket
        send_to_external_application(state_payload)

        # Log the incoming WebSocket data
        Rails.logger.info "Got message from Javascript LlamaBot Frontend: #{data.inspect}"
      rescue => e
        Rails.logger.error "Error in receive method: #{e.message}"
        send_message_to_frontend("error", e.message)
      end
    end

    def send_message_to_frontend(type, message, trace_info = nil)
      
      # Log trace info for debugging
      Rails.logger.info "TRACE INFO DEBUG: Type: #{type}, Has trace info: #{trace_info.present?}"

      message_data = {
        type: type,
        content: message
      }
      
      formatted_message = { message: message_data.to_json }.to_json
      
      ActionCable.server.broadcast "chat_channel_#{params[:session_id]}", formatted_message
    end

    private

    def state_builder_class
      LlamaBotRails.config.state_builder_class.constantize
    end

    def setup_external_websocket(connection_id)
      Thread.current[:connection_id] = connection_id
      Rails.logger.info "Setting up external websocket for connection: #{connection_id}"
      # endpoint = Async::HTTP::Endpoint.parse(ENV['LLAMABOT_WEBSOCKET_URL']) 
      uri = URI(ENV['LLAMABOT_WEBSOCKET_URL'])
      
      uri.scheme = 'wss'
      uri.scheme = 'ws' if ENV['DEVELOPMENT_ENVIRONMENT'] == 'true'

      endpoint = Async::HTTP::Endpoint.new(
          uri,
          ssl_context: OpenSSL::SSL::SSLContext.new.tap do |ctx|
              ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
              if ENV["STAGING_ENVIRONMENT"] == 'true'
                ctx.ca_file = '/usr/local/etc/ca-certificates/cert.pem'
                # M2 Air : ctx.ca_file = '/etc//ssl/cert.pem'
                ctx.cert = OpenSSL::X509::Certificate.new(File.read(File.expand_path('~/.ssl/llamapress/cert.pem')))
                ctx.key = OpenSSL::PKey::RSA.new(File.read(File.expand_path('~/.ssl/llamapress/key.pem')))
              elsif ENV['DEVELOPMENT_ENVIRONMENT'] == 'true'
                # do no ctx stuff
                ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE   
              else  # production
                ctx.ca_file ='/etc/ssl/certs/ca-certificates.crt'
              end
          end
      )

      # Initialize the connection and store it in an instance variable
      @external_ws_task = Async do |task|
        begin
          @external_ws_connection = Async::WebSocket::Client.connect(endpoint)
          Rails.logger.info "Connected to external WebSocket for connection: #{connection_id}"
          
          #Tell llamabot frontend that we've connected to the backend
          formatted_message = { message: {type: "external_ws_pong"} }.to_json
          ActionCable.server.broadcast "chat_channel_#{params[:session_id]}", formatted_message
          
          # Store tasks in instance variables so we can clean them up later
          @listener_task = task.async do
            listen_to_external_websocket(@external_ws_connection)
          end

          @keepalive_task = task.async do
            send_keep_alive_pings(@external_ws_connection)
          end

          # Wait for tasks to complete or connection to close
          [@listener_task, @keepalive_task].each(&:wait)
        rescue => e
          Rails.logger.error "Failed to connect to external WebSocket for connection #{connection_id}: #{e.message}"
        ensure
          # Clean up tasks if they exist
          @listener_task&.stop
          @keepalive_task&.stop
          @external_ws_connection&.close
        end
      end
    end

    # Listen for messages from the LlamaBot Backend
    def listen_to_external_websocket(connection)
      while message = connection.read

        #Try to fix the ping/pong issue keepliave
        # if message.type == :ping
        
        #   # respond with :pong
        #   connection.write(Async::WebSocket::Messages::ControlFrame.new(:pong, frame.data))
        #   connection.flush
        #   next
        # end
        # Extract the actual message content
        if message.buffer
          message_content = message.buffer  # Use .data to get the message content
        else
          message_content = message.content
        end

        Rails.logger.info "Received from external WebSocket: #{message_content}"
        
        begin
          parsed_message = JSON.parse(message_content)
          
          case parsed_message["type"]
          when "ai"
            # Add any additional handling for write_code messages here
            formatted_message = { message: {type: "ai", content: parsed_message['content']} }.to_json
          when "tool"
            # Add any additional handling for tool messages here
            formatted_message = { message: {type: "tool", content: parsed_message['content']} }.to_json
          when "error"
            Rails.logger.error "---------Received error message!----------"
            response = parsed_message['content']
            formatted_message = { message: message_content }.to_json
            Rails.logger.error "---------------------> Response: #{response}"
            Rails.logger.error "---------Completed error message!----------"
          when "pong"
            Rails.logger.debug "Received pong response"
            # Tell llamabot frontend that we've received a pong response, and we're still connected
            formatted_message = { message: {type: "pong"} }.to_json
          end
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse message as JSON: #{e.message}"
        end
        ActionCable.server.broadcast "chat_channel_#{params[:session_id]}", formatted_message
      end
    end

    ###
    def send_keep_alive_pings(connection)
      loop do
        ping_message = {
          type: 'ping',
          connection_id: @connection_id,
          connection_state: !connection.closed? ? 'connected' : 'disconnected',
          connection_class: connection.class.name
        }.to_json
        connection.write(ping_message)
        connection.flush
        Rails.logger.debug "Sent keep-alive ping: #{ping_message}"
        Async::Task.current.sleep(30)
      end
    rescue => e
      Rails.logger.error "Error in keep-alive ping: #{e.message} | Connection type: #{connection.class.name}"
    end

    # Send messages from the user to the LlamaBot Backend Socket
    def send_to_external_application(message)
      #   ChatMessage.create(content: message_content, user: current_user, chat_conversation: ChatConversation.last, ai_chat_message: true, created_at: Time.now)

      payload = message.to_json
      if @external_ws_connection
        begin
          @external_ws_connection.write(payload)
          @external_ws_connection.flush
          Rails.logger.info "Sent message to external WebSocket: #{payload}"
        rescue => e
          Rails.logger.error "Error sending message to external WebSocket: #{e.message}"
        end
      else
        Rails.logger.error "External WebSocket connection not established"
        # Optionally, you might want to attempt to reconnect here
      end
    end

    def validate_message(data)
      # This is a simple method that can be easily mocked
      true
    end
  end  # Single end statement to close the ChatChannel clas
end