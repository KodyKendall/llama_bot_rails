# lib/generators/llama_bot_rails/install/install_generator.rb
module LlamaBotRails
    module Generators
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        def allow_docker_host
          dev_config = "config/environments/development.rb"
          insertion = "  config.hosts << /host\\.docker\\.internal/  # Allow Docker agent to access Rails\n"
  
          unless File.read(dev_config).include?("host.docker.internal")
            inject_into_file dev_config, insertion, after: "Rails.application.configure do\n"
            say_status("updated", "Added host.docker.internal to development.rb", :green)
          end
        end

        def create_agent_prompt
            empty_directory "app/llama_bot/prompts"
            copy_file "agent_prompt.txt", "app/llama_bot/prompts/agent_prompt.txt"
        end

        def create_agent_state_builder
            empty_directory "app/llama_bot"
            template "agent_state_builder.rb.erb", "app/llama_bot/agent_state_builder.rb"
            say_status("created", "app/llama_bot/agent_state_builder.rb", :green)
        end
  
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
              config.llama_bot_rails.websocket_url      = ENV.fetch("LLAMABOT_WEBSOCKET_URL", "ws://localhost:8000/ws")
              config.llama_bot_rails.llamabot_api_url   = ENV.fetch("LLAMABOT_API_URL", "http://localhost:8000")
              config.llama_bot_rails.enable_console_tool = !Rails.env.production?

              # ------------------------------------------------------------------------
              # Custom State Builder
              # ------------------------------------------------------------------------
              # The gem uses `LlamaBotRails::AgentStateBuilder` by default.
              # Uncomment this line to use the builder in app/llama_bot/
              #
              # config.llama_bot_rails.state_builder_class = "#{app_name}::AgentStateBuilder"

              # ------------------------------------------------------------------------
              # Custom User Resolver
              # ------------------------------------------------------------------------
              # The gem uses `warden.user` by default.
              # Uncomment this line to use a custom user resolver in app/llama_bot/
              # Example: if you don’t use Devise, uncomment and tweak:
              # LlamaBotRails.user_resolver = ->(env) do
              #   # Rack session example
              #   if id = env['rack.session'][:account_id]
              #     Account.find_by(id: id)
              #   end
              # end
            end
          RUBY
        end
  
        def finish
          say "\n✅ LlamaBotRails installed! Visit http://localhost:3000/llama_bot/agent/chat\n", :green
        end

        private

        def app_name
          Rails.application.class.module_parent_name
        end
      end
    end
  end
  