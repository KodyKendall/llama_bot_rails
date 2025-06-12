require 'rails_helper'

RSpec.describe LlamaBotRails::ChatChannel, type: :channel do
  before do
    # Initialize a connection
    stub_connection
  end

  it "subscribes to the chat channel" do
    subscribe
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("llama_bot_rails_chat")
  end

  it "broadcasts a message when received" do
    subscribe
    message = "Hello, World!"
    
    expect {
      perform :receive, message: message
    }.to have_broadcasted_to("llama_bot_rails_chat").with(
      message: "Echo: #{message}"
    )
  end
end 