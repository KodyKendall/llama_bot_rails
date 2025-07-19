require "set"                                 # ← you call Set.new
require "llama_bot_rails/version"
require "llama_bot_rails/engine"
require "llama_bot_rails/llama_bot"
require "llama_bot_rails/agent_state_builder"
require "llama_bot_rails/controller_extensions"
require "llama_bot_rails/agent_auth"
require "llama_bot_rails/route_helper"

module LlamaBotRails
  # ------------------------------------------------------------------
  # Public configuration
  # ------------------------------------------------------------------

  # Allow-list of routes the agent may hit
  mattr_accessor :allowed_routes, default: Set.new

  # Lambda that receives Rack env and returns a user-like object
  class << self
    attr_accessor :user_resolver
    attr_accessor :current_user_resolver

    attr_accessor :sign_in_method
  end
  
  # Default (Devise / Warden); returns nil if Devise absent
  self.user_resolver = ->(user_id) do
    # Try to find a User model, fallback to nil if not found
    # byebug
    if defined?(Devise)
      default_scope = Devise.default_scope # e.g., :user
      user_class = Devise.mappings[default_scope].to
      user_class.find_by(id: user_id)
    else
      Rails.logger.warn("[[LlamaBot]] Implement a user_resolver! in your app to resolve the user from the user_id.")
      nil
    end
  end

  # Default (Devise / Warden); returns nil if Devise absent
  self.current_user_resolver = ->(env) do
    # Try to find a User model, fallback to nil if not found
    if defined?(Devise)
      env['warden']&.user
    else
      Rails.logger.warn("[[LlamaBot]] Implement a current_user_resolver! in your app to resolve the current user from the environment.")
      nil
    end
  end

  # Lambda that receives Rack env and user_id, and sets the user in the warden session
  # Default sign-in method is configured for Devise with Warden.
  self.sign_in_method = ->(env, user) do
    env['warden']&.set_user(user)
  end

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