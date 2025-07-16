require 'rails_helper'

RSpec.describe LlamaBotRails::ChatChannel, type: :channel do
  before do
    # Initialize a connection with session_id
    stub_connection(session_id: 'test_session_123')
    
    # Create a mock state builder class and instance
    mock_builder_instance = double('MockStateBuilder')
    allow(mock_builder_instance).to receive(:build).and_return({ test: 'data' })
    
    mock_builder_class = double('MockStateBuilderClass')
    allow(mock_builder_class).to receive(:new).and_return(mock_builder_instance)
    
    # Mock the state_builder_class method to return our mock class
    allow_any_instance_of(LlamaBotRails::ChatChannel).to receive(:state_builder_class).and_return(mock_builder_class)
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

  it "generates a secure api token when message is received" do
    # Mock the current_user_resolver to return a user
    mock_user = double('User', id: 123)
    allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(env) { mock_user })
    
    # Create a connection with proper env
    mock_env = { 'warden' => double('warden', user: mock_user) }
    stub_connection(session_id: 'test_session_123', env: mock_env)
    subscribe(session_id: 'test_session_123')
    
    # Prevent any external calls or complex setup - we just want to test token generation
    allow_any_instance_of(LlamaBotRails::ChatChannel).to receive(:validate_message)
    allow_any_instance_of(LlamaBotRails::ChatChannel).to receive(:send_to_external_application)
    
    # Mock Thread.new to prevent background thread from running
    allow(Thread).to receive(:new).and_return(double('thread', join: nil))
    
    # The api token is now generated when receiving a message, not during subscription
    perform :receive, { message: "test message", thread_id: "test_thread" }
    
    expect(subscription.instance_variable_get(:@api_token)).to be_present
  end
end