require "llama_bot_rails/version"
require "llama_bot_rails/engine"

# require "llama_bot_rails/railtie" # We don't need this, as we're loading the LlamaBot path directly in the engine.
require "llama_bot_rails/llama_bot"
require "llama_bot_rails/agent_state_builder"

module LlamaBotRails
  class << self
    def config
      Rails.application.config.llama_bot_rails
    end

    def agent_prompt_path
      Rails.root.join("app", "llama_bot", "prompts", "agent_prompt.txt")
    end

    def agent_prompt_text
      if File.exist?(agent_prompt_path)
        File.read(agent_prompt_path)
      else
        "You are LlamaBot, a helpful assistant." #Fallback default.
      end
    end

    def add_instruction_to_agent_prompt!(new_instruction)
      FileUtils.mkdir_p(agent_prompt_path.dirname)
      File.write(agent_prompt_path, "\n#{new_instruction}", mode: 'a')
    end

    def send_agent_message(agent_params)
      LlamaBot.send_agent_message(agent_params)
    end
  end
end
