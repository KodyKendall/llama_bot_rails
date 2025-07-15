require "set"                                 # ← you call Set.new
require "llama_bot_rails/version"
require "llama_bot_rails/engine"
require "llama_bot_rails/llama_bot"
require "llama_bot_rails/agent_state_builder"
require "llama_bot_rails/controller_extensions"
require "llama_bot_rails/agent_auth"

module LlamaBotRails
  # ------------------------------------------------------------------
  # Public configuration
  # ------------------------------------------------------------------

  # Allow-list of routes the agent may hit
  mattr_accessor :allowed_routes, default: Set.new

  # Lambda that receives Rack env and returns a user-like object
  class << self
    attr_accessor :user_resolver
  end
  # Default (Devise / Warden); returns nil if Devise absent
  self.user_resolver = ->(env) { env['warden']&.user }

  # Convenience helper for host-app initializers
  def self.config = Rails.application.config.llama_bot_rails

  # ------------------------------------------------------------------
  # Prompt helpers
  # ------------------------------------------------------------------
  def self.agent_prompt_path  = Rails.root.join("app", "llama_bot", "prompts", "agent_prompt.txt")

  def self.agent_prompt_text
    File.exist?(agent_prompt_path) ? File.read(agent_prompt_path) : "You are LlamaBot, a helpful assistant."
  end

  def self.add_instruction_to_agent_prompt!(str)
    FileUtils.mkdir_p(agent_prompt_path.dirname)
    File.write(agent_prompt_path, "\n#{str}", mode: "a")
  end

  # ------------------------------------------------------------------
  # Bridge to backend service
  # ------------------------------------------------------------------
  def self.send_agent_message(params) = LlamaBot.send_agent_message(params)
end
