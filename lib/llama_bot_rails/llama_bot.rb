require 'net/http'
require 'json'
require 'uri'

module LlamaBotRails
  #This class is responsible for initiating HTTP requests to the FastAPI backend that takes us to LangGraph.
  class LlamaBot
    def self.get_threads
      uri = URI('http://localhost:8000/threads')
      response = Net::HTTP.get_response(uri)
      JSON.parse(response.body)
    rescue => e
      Rails.logger.error "Error fetching threads: #{e.message}"
      []
    end

    def self.get_chat_history(thread_id)
      uri = URI("http://localhost:8000/chat-history/#{thread_id}")
      response = Net::HTTP.get_response(uri)
      JSON.parse(response.body)
    rescue => e
      Rails.logger.error "Error fetching chat history: #{e.message}"
      []
    end
    
    def self.send_agent_message(agent_params)
      return enum_for(__method__, agent_params) unless block_given?

      uri = URI("http://localhost:8000/llamabot-chat-message")
      http = Net::HTTP.new(uri.host, uri.port)
      
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = agent_params.to_json

      # Stream the response instead of buffering it
      http.request(request) do |response|
        if response.code.to_i == 200
          buffer = ''
          
          response.read_body do |chunk|
            Rails.logger.info "[[LlamaBot]] Received chunk in LlamaBot.rb: #{chunk}"
            buffer += chunk
            
            # Process complete lines (ended with \n)
            while buffer.include?("\n")
              line, buffer = buffer.split("\n", 2)
              if line.strip.present?
                begin
                  Rails.logger.info "[[LlamaBot]] Sending AI chunk in LlamaBot.rb: #{line}"
                  yield JSON.parse(line)
                rescue JSON::ParserError => e
                  Rails.logger.error "Parse error: #{e.message}"
                end
              end
            end
          end
          
          # Process any remaining data in buffer
          if buffer.strip.present?
            begin
              yield JSON.parse(buffer)
            rescue JSON::ParserError => e
              Rails.logger.error "Final buffer parse error: #{e.message}"
            end
          end
        end
      end
    rescue => e
      Rails.logger.error "Error sending agent message: #{e.message}"
      { error: e.message }
    end
  end
end