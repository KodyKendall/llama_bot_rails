LlamaBotRails::Engine.routes.draw do
    post "agent/command", to: "agent#command"
    get "agent/chat", to: "agent#chat"
end
