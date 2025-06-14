require 'rails_helper'

RSpec.describe LlamaBotRails::ChatChannel, type: :channel do
  before do
    # Initialize a connection with session_id
    stub_connection(session_id: 'test_session_123')
    
    # Mock the LlamaBotRails configuration
    allow(LlamaBotRails).to receive_message_chain(:config, :state_builder_class).and_return('MockStateBuilder')
    
    # Create a mock state builder
    mock_builder = double('MockStateBuilder')
    allow(mock_builder).to receive(:new).and_return(mock_builder)
    allow(mock_builder).to receive(:build).and_return({ test: 'data' })
    stub_const('MockStateBuilder', mock_builder)
  end

  it "subscribes to the chat channel" do
    subscribe(session_id: 'test_session_123')
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("chat_channel_test_session_123")
  end

  it "processes received messages" do
    subscribe(session_id: 'test_session_123')
    message_data = { message: "Hello, World!", thread_id: "test_thread" }
    
    # Mock the external websocket setup and sending
    allow(subscription).to receive(:setup_external_websocket)
    allow(subscription).to receive(:send_to_external_application)
    
    # This should not raise an error
    expect {
      perform :receive, message_data
    }.not_to raise_error
  end

  it "generates a secure api token" do
    subscribe(session_id: 'test_session_123')
    # The api token is generated in the subscribed method
    expect(subscription.instance_variable_get(:@api_token)).to be_present
  end
end