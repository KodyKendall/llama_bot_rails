# lib/generators/llama_bot_rails/install/install_generator.rb
module LlamaBotRails
    module Generators
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)
  
        def mount_engine
            say <<~MSG, :yellow
                ⚠️ NOTE: LlamaBotRails requires ActionCable to be available on the frontend.

                If you're using ImportMap (Rails 7 default), run:

                    bin/importmap pin @rails/actioncable

                And in app/javascript/application.js, add:

                    import * as ActionCable from "@rails/actioncable"
                    window.ActionCable = ActionCable

                If you're using Webpacker or jsbundling-rails:
                    Add @rails/actioncable via yarn/npm
                    And import + expose it the same way in your JS pack.

                📘 See README → “JavaScript Setup” for full details.
                
                MSG

          route 'mount LlamaBotRails::Engine => "/llama_bot"'
        end
  
        def create_initializer
          create_file "config/initializers/llama_bot_rails.rb", <<~RUBY
            Rails.application.configure do
              config.llama_bot_rails.websocket_url = ENV.fetch("LLAMABOT_WEBSOCKET_URL", "ws://localhost:8000/ws")
              config.llama_bot_rails.enable_console_tool = !Rails.env.production?
            end
          RUBY
        end
  
        def finish
          say "\n✅ LlamaBotRails installed! Visit http://localhost:3000/llama_bot/agent/chat\n", :green
        end
      end
    end
  end
  