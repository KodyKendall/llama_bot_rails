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
    
    def self.send_agent_message(message, thread_id=nil, agent_name=nil)
      uri = URI("http://localhost:8000/llamabot-chat-message")

      # Create the HTTP request with proper headers
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      
      # Build the request body to match the Pydantic ChatMessage schema
      request_body = {
        message: message
      }
      
      # Only include optional fields if they have values
      request_body[:thread_id] = thread_id if thread_id.present?
      request_body[:agent] = agent_name if agent_name.present?
      
      request.body = request_body.to_json
      
      response = http.request(request)

      if response.code.to_i == 200
        # Step 1: Get the body
        body = response.body

        # Step 2: Split by newline in case there are multiple JSON blobs
        json_blobs = body.strip.split("\n")

        # Step 3: Parse each blob
        parsed_objects = json_blobs.map { |blob| JSON.parse(blob) }

        # Now you have an array of parsed JSON (as Ruby objects)
        return JSON(parsed_objects[0])

      else
        Rails.logger.error "HTTP Error #{response.code}: #{response.body}"
        { 
          success: false,
          error: "HTTP #{response.code}", 
          body: response.body 
        }
      end
    rescue => e
      Rails.logger.error "Error sending agent message: #{e.message}"
      { error: e.message }
    end
  end
end