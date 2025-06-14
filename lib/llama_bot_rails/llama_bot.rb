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
  end
end