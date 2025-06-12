module LlamaBotRails
  class Engine < ::Rails::Engine
    isolate_namespace LlamaBotRails

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: 'spec/factories'
    end

    initializer "llama_bot_rails.assets.precompile" do |app|
      app.config.assets.precompile += %w( llama_bot_rails/application.js )
    end
  end
end
