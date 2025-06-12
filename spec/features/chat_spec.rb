require 'rails_helper'

RSpec.feature "Chat", type: :feature do
  before do
    driven_by(:selenium_chrome_headless)
  end

  scenario "User can send and receive messages" do
    visit "/llama_bot/agent/chat"
    
    # Check if the chat interface is loaded
    expect(page).to have_selector(".chat-container")
    expect(page).to have_selector("#message-input")
    expect(page).to have_selector("button", text: "Send")

    # Send a message
    fill_in "message-input", with: "Hello, LlamaBot!"
    click_button "Send"

    # Check if the message appears in the chat
    expect(page).to have_selector(".user-message", text: "Hello, LlamaBot!")
    
    # Check if we receive a response
    expect(page).to have_selector(".bot-message", text: /Echo: Hello, LlamaBot!/)
  end

  scenario "User can send message using Enter key" do
    visit "/llama_bot/agent/chat"
    
    # Send a message using Enter key
    fill_in "message-input", with: "Hello, LlamaBot!"
    find("#message-input").send_keys(:enter)

    # Check if the message appears in the chat
    expect(page).to have_selector(".user-message", text: "Hello, LlamaBot!")
    expect(page).to have_selector(".bot-message", text: /Echo: Hello, LlamaBot!/)
  end
end 