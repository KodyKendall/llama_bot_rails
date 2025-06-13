module LlamaBotRails
  require 'llama_bot_rails/agent_state_builder'

  class Engine < ::Rails::Engine
    isolate_namespace LlamaBotRails

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: 'spec/factories'
    end

    config.llama_bot_rails = ActiveSupport::OrderedOptions.new

    initializer "llama_bot_rails.assets.precompile" do |app|
      app.config.assets.precompile += %w( llama_bot_rails/application.js )
    end

    initializer "llama_bot_rails.defaults" do |app|
      app.config.llama_bot_rails.state_builder_class = "LlamaBotRails::AgentStateBuilder"
    end
  end
end
