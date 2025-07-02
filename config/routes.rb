LlamaBotRails::Engine.routes.draw do
  post "agent/command", to: "agent#command"
  get "agent/chat", to: "agent#chat"
  get "agent/chat_ws", to: "agent#chat_ws"
  get "agent/threads", to: "agent#threads"
  get "agent/chat-history/:thread_id", to: "agent#chat_history"
  post "agent/send_message", to: "agent#send_message"
  get "agent/test_streaming", to: "agent#test_streaming"
end