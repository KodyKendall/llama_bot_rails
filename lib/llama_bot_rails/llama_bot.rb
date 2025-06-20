require 'net/http'
require 'json'
require 'uri'

module LlamaBotRails
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
      uri = URI("http://localhost:8000/llamabot-chat-message") #TODO: Should there be a thread_id? What about an agent_name?

      # Let's start simple for now.?
      # Must match this Python schema: 
      #@app.post("/chat-message")
      #async def llama_bot_message(chat_message: ChatMessage):

      # class ChatMessage(BaseModel):
      #   message: str
      #   thread_id: str = None  # Optional thread_id parameter
      #   agent: str = None  # Optional agent parameter
    

      response = Net::HTTP.post(uri, {message: message, thread_id: thread_id, agent: agent_name}.to_json)
      JSON.parse(response.body)
    rescue => e
      Rails.logger.error "Error sending agent message: #{e.message}"
      []
    end
  end
end