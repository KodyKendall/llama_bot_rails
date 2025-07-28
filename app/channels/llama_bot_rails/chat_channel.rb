require 'async'
require 'async/http'
require 'async/websocket'

require 'json'  # Ensure JSON is required if not already

# Why support both a websocket connection, (chat_channel.rb), and a non-websocket SSE connection? %>
# Rails 6 wasn’t working with our ActionCable websocket connection, so I wanted to implement SSE as well.

# We want to support a generic HTML interface that isn’t dependent on rails. (In case the Rails server goes down for whatever reason, we don’t lose access to LlamaBot).
# Why have chat_channel.rb at all?

# Because Ruby on Rails lacks good tooling to handle real-time interaction, that isn’t through ActionCable. 
# For “cancel” requests. Websocket is a 2 way connection, so we can send a ‘cancel’ in. 
# To support legacy LlamaPress stuff. 
# We chose to implement it with ActionCable plus Async Websockets.
# But, it’s Ruby on Rails specific, and is best for UI/UX experiences.

# SSE is better for other clients that aren’t Ruby on Rails specific, and if you want to handle just a simple SSE approach.
# This does add some complexity though.

# We now have 2 different paradigms of front-end JavaScript consuming from LlamaBot
# ActionCable consumption
# StreamedResponse consumption.

# We also have 2 new middleware layers:
# ActionCable <-> chat_channel.rb <-> /ws <-> request_handler.py
# HTTPS <-> agent_controller.rb <-> LlamaBot.rb <-> FastAPI HTTPS

# So this increases our overall surface area for the application.

# This is deprecated and will be removed over time, to move towards a simple SSE approach.


module LlamaBotRails
  class ChatChannel < ApplicationCable::Channel
    # _chat.html.erb front-end subscribes to this channel in _websocket.html.erb.
    def subscribed
      begin
        stream_from "chat_channel_#{params[:session_id]}" # Public stream for session-based messages <- this is the channel we're subscribing to in _websocket.html.erb
        Rails.logger.info "[LlamaBot] Subscribed to chat channel with session ID: #{params[:session_id]}"
        
        @connection_id = SecureRandom.uuid
        Rails.logger.info "[LlamaBot] Created new connection with ID: #{@connection_id}"
        Rails.logger.info "[LlamaBot] Secure API token generated."

        # Use a begin/rescue block to catch thread creation errors
      begin

        @worker = Thread.new do
            Thread.current[:connection_id] = @connection_id
          Thread.current.abort_on_exception = true  # This will help surface errors
          setup_external_websocket(@connection_id)
        end
      rescue => e
        Rails.logger.error "[LlamaBot] Error in WebSocket subscription: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Send error message to frontend before rejecting
        begin
          send_message_to_frontend("error", "Failed to establish chat connection: #{e.message}")
        rescue => send_error
          Rails.logger.error "[LlamaBot] Could not send error to frontend: #{send_error.message}"
        end
        
        reject # Reject the connection if there's an error
        end
      rescue ThreadError => e
        Rails.logger.error "[LlamaBot] Failed to allocate thread: #{e.message}"
        # Handle the error gracefully - potentially notify the client
        send_message_to_frontend("error", "Failed to establish connection: #{e.message}")
      end
    end

    def unsubscribed
      connection_id = @connection_id
      Rails.logger.info "[LlamaBot] Unsubscribing connection: #{connection_id}"
      
      begin
        # Only kill the worker if it belongs to this connection
        if @worker && @worker[:connection_id] == connection_id
          begin
            @worker.kill
            @worker = nil
            Rails.logger.info "[LlamaBot] Killed worker thread for connection: #{connection_id}"
          rescue => e
            Rails.logger.error "[LlamaBot] Error killing worker thread: #{e.message}"
          end
        end

        # Clean up async tasks with better error handling
        begin
          @listener_task&.stop rescue nil
          @keepalive_task&.stop rescue nil
          @external_ws_task&.stop rescue nil
        rescue => e
          Rails.logger.error "[LlamaBot] Error stopping async tasks: #{e.message}"
        end
        
        # Clean up the connection
        if @external_ws_connection
          begin
            @external_ws_connection.close
            Rails.logger.info "[LlamaBot] Closed external WebSocket connection for: #{connection_id}"
          rescue => e
            Rails.logger.warn "[LlamaBot] Could not close WebSocket connection: #{e.message}"
          end
        end
        
        # Force garbage collection in development/test environments to help clean up
        if !Rails.env.production?
          GC.start
        end
      rescue => e
        Rails.logger.error "[LlamaBot] Fatal error during channel unsubscription: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

    # Receive messages from _chat.html.erb frontend and send to llamabot FastAPI backend, frontend comes from the llamabot/_chat.html.erb chatbot, sent
    # through external websocket to FastAPI/Python backend.
    def receive(data)
      begin
        #used to validate the message before it's sent to the llamabot-backend.

        # Get the currently logged in user from the environment.
        current_user = LlamaBotRails.current_user_resolver.call(connection.env)

        @api_token = Rails.application.message_verifier(:llamabot_ws).generate(
          { session_id: SecureRandom.uuid, user_id: current_user&.id},
          expires_in: 30.minutes
        )

        #This could be an example of how we might implement hooks & filters in the future.
        validate_message(data) #Placeholder for now, we are using this to mock errors being thrown. In the future, we can add actual validation logic.        
        # Forward the processed data to the LlamaBot Backend Socket
        message = data["message"]

        builder = state_builder_class.new(
          params: data,
          context: { api_token: @api_token }.with_indifferent_access
        )

        # 2. Construct the LangGraph-ready state
        state_payload = builder.build

        # 3. Ship it over the existing WebSocket
        send_to_external_application(state_payload)

        # Log the incoming WebSocket data
        Rails.logger.info "[LlamaBot] Got message from Javascript LlamaBot Frontend: #{data.inspect}"
      rescue => e
        Rails.logger.error "[LlamaBot] Error in receive method: #{e.message}"
        Rails.logger.error "[LlamaBot] Backtrace: #{e.backtrace.join("\n")}"
        send_message_to_frontend("error", e.message)
      end
    end

    def send_message_to_frontend(type, message, trace_info = nil)
      
      # Log trace info for debugging
      Rails.logger.info "[LlamaBot] TRACE INFO DEBUG: Type: #{type}, Has trace info: #{trace_info.present?}"

      message_data = {
        type: type,
        content: message
      }
      
      formatted_message = { message: message_data.to_json }.to_json
      
      ActionCable.server.broadcast "chat_channel_#{params[:session_id]}", formatted_message
    end

    private

    def state_builder_class
      builder_class_name = LlamaBotRails.config.state_builder_class || 'LlamaBotRails::AgentStateBuilder'

      begin
        builder_class_name.constantize
      rescue NameError => e
        # If it's not the default class, try to manually load from app/llama_bot
        if builder_class_name != 'LlamaBotRails::AgentStateBuilder'
          llama_bot_file = Rails.root.join("app", "llama_bot", "agent_state_builder.rb")
          if llama_bot_file.exist?
            Rails.logger.info "[LlamaBot] Autoload failed, attempting to manually load #{llama_bot_file}"
            begin
              load llama_bot_file.to_s
              return builder_class_name.constantize
            rescue => load_error
              Rails.logger.error "[LlamaBot] Manual load failed: #{load_error.message}"
            end
          end
        end
        
        raise NameError, "Could not load state builder class '#{builder_class_name}'. Make sure it's defined in app/llama_bot/agent_state_builder.rb or is available in your autoload paths. Original error: #{e.message}"
      end
    end

    def setup_external_websocket(connection_id)
      Thread.current[:connection_id] = connection_id
      Rails.logger.info "[LlamaBot] Setting up external websocket for connection: #{connection_id}"
      
      # Check if the WebSocket URL is configured
      websocket_url = Rails.application.config.llama_bot_rails.websocket_url
      if websocket_url.blank?
        Rails.logger.warn "[LlamaBot] LlamaBot Websocket URL is not configured in the config/initializers/llama_bot_rails.rb file, skipping external WebSocket setup"
        return
      end
      
      uri = URI(websocket_url)
      
      uri.scheme = 'wss'
      uri.scheme = 'ws' if Rails.env.development?

      endpoint = Async::HTTP::Endpoint.new(
          uri,
          ssl_context: OpenSSL::SSL::SSLContext.new.tap do |ctx|
              ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
              if Rails.env.staging?
                ctx.ca_file = '/usr/local/etc/ca-certificates/cert.pem'
                # M2 Air : ctx.ca_file = '/etc//ssl/cert.pem'
                ctx.cert = OpenSSL::X509::Certificate.new(File.read(File.expand_path('~/.ssl/llamapress/cert.pem')))
                ctx.key = OpenSSL::PKey::RSA.new(File.read(File.expand_path('~/.ssl/llamapress/key.pem')))
              elsif Rails.env.development?
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
          Rails.logger.info "[LlamaBot] Connected to external WebSocket for connection: #{connection_id}"
          
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
          Rails.logger.error "[LlamaBot] Failed to connect to external WebSocket for connection #{connection_id}: #{e.message}"
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
      begin
        while message = connection.read
          # Extract the actual message content
          message_content = message.buffer if message.buffer
          next unless message_content.present?

          Rails.logger.info "[LlamaBot] Received from external WebSocket: #{message_content}"

          begin
            parsed_message = JSON.parse(message_content)
            
            formatted_message = { message: {type: parsed_message["type"], content: parsed_message['content'], base_message: parsed_message["base_message"]} }.to_json
            case parsed_message["type"]
            when "error"
              Rails.logger.error "[LlamaBot] ---------Received error message!----------"
              response = parsed_message['content']
              formatted_message = { message: message_content }.to_json
              Rails.logger.error "[LlamaBot] ---------------------> Response: #{response}"
              Rails.logger.error "[LlamaBot] ---------Completed error message!----------"
            when "pong"
              # Tell llamabot frontend that we've received a pong response, and we're still connected
              formatted_message = { message: {type: "pong"} }.to_json
            end
            ActionCable.server.broadcast "chat_channel_#{params[:session_id]}", formatted_message
          rescue JSON::ParserError => e
            Rails.logger.error "[LlamaBot] Failed to parse message as JSON: #{e.message}"
            # Continue to the next message without crashing the listener.
            next
          end
        end
      rescue IOError, Errno::ECONNRESET => e
        # This is a recoverable error. Log it and allow the task to end gracefully.
        # The `ensure` block in `setup_external_websocket` will handle the cleanup.
        Rails.logger.warn "[LlamaBot] Connection lost while listening: #{e.message}. The connection will be closed."
      end
    end

    ###
    def send_keep_alive_pings(connection)
      loop do
        # Stop the loop gracefully if the connection has already been closed.
        break if connection.closed?
        
        begin
          ping_message = {
            type: 'ping',
            connection_id: @connection_id,
            connection_state: !connection.closed? ? 'connected' : 'disconnected',
            connection_class: connection.class.name
          }.to_json
          connection.write(ping_message)
          connection.flush
          Rails.logger.debug "[LlamaBot] Sent keep-alive ping: #{ping_message}"
        rescue IOError, Errno::ECONNRESET => e
          Rails.logger.warn "[LlamaBot] Could not send ping, connection likely closed: #{e.message}"
          # Break the loop to allow the task to terminate gracefully.
          break
        end

        Async::Task.current.sleep(30)
      end
    end

    # Send messages from the user to the LlamaBot Backend Socket
    def send_to_external_application(message)
      #   ChatMessage.create(content: message_content, user: current_user, chat_conversation: ChatConversation.last, ai_chat_message: true, created_at: Time.now)

      payload = message.to_json
      if @external_ws_connection
        begin
          @external_ws_connection.write(payload)
          @external_ws_connection.flush
          Rails.logger.info "[LlamaBot] Sent message to external WebSocket: #{payload}"
        rescue => e
          Rails.logger.error "[LlamaBot] Error sending message to external WebSocket: #{e.message}"
        end
      else
        Rails.logger.error "[LlamaBot] External WebSocket connection not established"
        # Optionally, you might want to attempt to reconnect here
      end
    end

    def validate_message(data)
      # This is a simple method that can be easily mocked
      true
    end
  end  # Single end statement to close the ChatChannel clas
end