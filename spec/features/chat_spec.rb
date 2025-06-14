require 'rails_helper'

RSpec.feature "Chat", type: :feature, js: true do
  scenario "User can send and receive messages" do
    visit "/llama_bot_rails/agent/chat"
    
    # Check if the chat interface is loaded
    expect(page).to have_selector(".chat-container")
    expect(page).to have_selector("#message-input")
    expect(page).to have_selector("button", text: "Send")

    # Send a message
    fill_in "message-input", with: "Hello, LlamaBot!"
    click_button "Send"

    # Check if the message appears in the chat
    expect(page).to have_selector(".human-message", text: "Hello, LlamaBot!")
  end

  scenario "User can send message using Enter key" do
    visit "/llama_bot_rails/agent/chat"
    
    # Send a message using Enter key
    fill_in "message-input", with: "Hello, LlamaBot!"
    find("#message-input").send_keys(:enter)

    # Check if the message appears in the chat
    expect(page).to have_selector(".human-message", text: "Hello, LlamaBot!")
  end
end 
