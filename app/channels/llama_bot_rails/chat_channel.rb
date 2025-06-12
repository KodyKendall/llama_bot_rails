# llama_bot_rails/app/channels/llama_bot_rails/chat_channel.rb
module LlamaBotRails
    class ChatChannel < ApplicationCable::Channel
      def subscribed
        stream_from "llama_bot_rails_chat"
      end
  
      def receive(data)
        # Process the incoming message
        message = data['message']
        
        # Here you can add your message processing logic
        # For now, we'll just echo it back
        response = "Echo: #{message}"
        
        # Broadcast the response back to all subscribers
        ActionCable.server.broadcast("llama_bot_rails_chat", {
          message: response
        })
      end
    end
  end
  