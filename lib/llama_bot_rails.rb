require "llama_bot_rails/version"
require "llama_bot_rails/engine"

module LlamaBotRails
  class << self
    def config
      Rails.application.config.llama_bot_rails
    end
  end
end
