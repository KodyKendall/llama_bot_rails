LlamaBotRails::Engine.routes.draw do
  post "agent/command", to: "agent#command"
  get "agent/chat", to: "agent#chat"
  get "agent/threads", to: "agent#threads"
  get "agent/chat-history/:thread_id", to: "agent#chat_history"
  post "agent/send_message", to: "agent#send_message"
end