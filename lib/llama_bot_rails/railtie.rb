module LlamaBotRails
  class Railtie < ::Rails::Railtie
    config.before_configuration do |app|
      llama_bot_path = Rails.root.join("app", "llama_bot")

      # Add to autoload paths if it exists and isn't already included
      if llama_bot_path.exist? && !app.config.autoload_paths.include?(llama_bot_path.to_s)
        app.config.autoload_paths << llama_bot_path.to_s
        Rails.logger&.info "[LlamaBot] Added #{llama_bot_path} to autoload_paths"
      end

      # Add to eager load paths if it exists and isn't already included  
      if llama_bot_path.exist? && !app.config.eager_load_paths.include?(llama_bot_path.to_s)
        app.config.eager_load_paths << llama_bot_path.to_s
        Rails.logger&.info "[LlamaBot] Added #{llama_bot_path} to eager_load_paths"
      end
    end
  end
end 