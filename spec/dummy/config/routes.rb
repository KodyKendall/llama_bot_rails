Rails.application.routes.draw do
  mount LlamaBotRails::Engine => "/llama_bot_rails"
end
