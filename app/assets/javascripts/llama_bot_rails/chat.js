// llama_bot_rails/app/assets/javascripts/llama_bot_rails/chat.js

const chatChannel = ActionCable.createConsumer().subscriptions.create(
    { channel: "LlamaBotRails::ChatChannel" },
    {
      received(data) {
        console.log("Received:", data.message);
      },
      connected() {
        console.log("Connected to llama_bot_rails_chat");
      }
    }
);