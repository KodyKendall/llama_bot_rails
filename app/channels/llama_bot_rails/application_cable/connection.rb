# llama_bot_rails/app/channels/llama_bot_rails/application_cable/connection.rb
module LlamaBotRails
    module ApplicationCable
      class Connection < ActionCable::Connection::Base
        identified_by :uuid
  
        def connect
          self.uuid = SecureRandom.uuid
        end
      end
    end
  end
  