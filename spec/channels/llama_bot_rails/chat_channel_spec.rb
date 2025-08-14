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

  describe "agent_state_builder_class parameter" do
    # Remove the global mock for these tests
    before do
      allow_any_instance_of(LlamaBotRails::ChatChannel).to receive(:state_builder_class).and_call_original
    end

    context "when agent_state_builder_class is provided in params" do
      it "uses the provided class name" do
        custom_builder_class = "CustomAgentStateBuilder"
        subscribe(session_id: 'test_session_123', agent_state_builder_class: custom_builder_class)
        
        expect(subscription).to be_confirmed
        expect(subscription.instance_variable_get(:@agent_state_builder_class)).to eq(custom_builder_class)
      end
    end

    context "when agent_state_builder_class is not provided" do
      context "and config.state_builder_class is set" do
        before do
          allow(LlamaBotRails.config).to receive(:state_builder_class).and_return("ConfiguredStateBuilder")
        end

        it "uses the configured state builder class" do
          subscribe(session_id: 'test_session_123')
          
          expect(subscription).to be_confirmed
          expect(subscription.instance_variable_get(:@agent_state_builder_class)).to eq("ConfiguredStateBuilder")
        end
      end

      context "and config.state_builder_class is not set" do
        before do
          allow(LlamaBotRails.config).to receive(:state_builder_class).and_return(nil)
        end

        it "defaults to LlamaBotRails::AgentStateBuilder" do
          subscribe(session_id: 'test_session_123')
          
          expect(subscription).to be_confirmed
          expect(subscription.instance_variable_get(:@agent_state_builder_class)).to eq('LlamaBotRails::AgentStateBuilder')
        end
      end
    end

    context "when agent_state_builder_class is blank (empty string)" do
      context "and config.state_builder_class is set" do
        before do
          allow(LlamaBotRails.config).to receive(:state_builder_class).and_return("ConfiguredStateBuilder")
        end

        it "uses the configured state builder class" do
          subscribe(session_id: 'test_session_123', agent_state_builder_class: '')
          
          expect(subscription).to be_confirmed
          expect(subscription.instance_variable_get(:@agent_state_builder_class)).to eq("ConfiguredStateBuilder")
        end
      end
    end

    describe "state_builder_class method" do
      let(:mock_custom_builder_class) { double('CustomBuilderClass') }
      let(:mock_custom_builder_instance) { double('CustomBuilderInstance') }

      before do
        # Allow the mock to be constantized
        allow(mock_custom_builder_instance).to receive(:build).and_return({ custom: 'state' })
        allow(mock_custom_builder_class).to receive(:new).and_return(mock_custom_builder_instance)
      end

      it "uses the instance variable set during subscription" do
        # Subscribe with a custom builder class
        subscribe(session_id: 'test_session_123', agent_state_builder_class: 'MyCustomBuilder')
        
        # Mock constantize to return our mock class
        allow_any_instance_of(String).to receive(:constantize) do |str|
          if str == 'MyCustomBuilder'
            mock_custom_builder_class
          else
            raise NameError, "uninitialized constant #{str}"
          end
        end

        # Access the private method using send
        builder_class = subscription.send(:state_builder_class)
        
        expect(builder_class).to eq(mock_custom_builder_class)
      end

      it "handles NameError when custom class cannot be loaded" do
        # Subscribe with a non-existent custom builder class
        subscribe(session_id: 'test_session_123', agent_state_builder_class: 'NonExistentBuilder')
        
        # Mock Rails.root to avoid file system operations
        mock_path = double('path')
        allow(mock_path).to receive(:join).and_return(mock_path)
        allow(mock_path).to receive(:exist?).and_return(false)
        allow(Rails).to receive(:root).and_return(mock_path)
        
        # Mock constantize to raise NameError
        allow_any_instance_of(String).to receive(:constantize).and_raise(NameError, "uninitialized constant NonExistentBuilder")
        
        # Expect it to raise NameError when trying to constantize
        expect {
          subscription.send(:state_builder_class)
        }.to raise_error(NameError)
      end
    end
  end
end