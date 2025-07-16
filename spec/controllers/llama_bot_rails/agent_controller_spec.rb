require 'rails_helper'

RSpec.describe LlamaBotRails::AgentController, type: :controller do
  routes { LlamaBotRails::Engine.routes }

  let(:valid_token) { Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test', user_id: 123}) }
  let(:mock_user) { double('User', id: 123) }

  before do
    # Mock user resolvers
    allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(env) { mock_user })
    allow(LlamaBotRails).to receive(:user_resolver).and_return(->(id) { mock_user if id == 123 })
    allow(LlamaBotRails).to receive(:sign_in_method).and_return(->(env, user) { true })
  end

  describe 'GET #chat' do
    it 'renders the chat template' do
      get :chat
      expect(response).to be_successful
    end
  end

  describe 'GET #chat_ws' do
    it 'renders the websocket chat template' do
      get :chat_ws
      expect(response).to be_successful
    end
  end

  describe 'POST #command' do
    let(:command) { 'puts "Hello World"' }

    context 'with valid agent authentication' do
      before do
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
      end

      context 'when console tool is enabled' do
        before do
          allow(Rails.application.config.llama_bot_rails).to receive(:enable_console_tool).and_return(true)
        end

        it 'executes the command and returns result' do
          post :command, params: { command: command }
          
          expect(response).to be_successful
          parsed_response = JSON.parse(response.body)
          expect(parsed_response).to have_key('output')
          expect(parsed_response).to have_key('result')
        end

        it 'captures stdout output' do
          post :command, params: { command: 'puts "test output"' }
          
          parsed_response = JSON.parse(response.body)
          expect(parsed_response['output']).to eq('test output')
        end

        it 'captures return value' do
          post :command, params: { command: '2 + 2' }
          
          parsed_response = JSON.parse(response.body)
          expect(parsed_response['result']).to eq(4)
        end

        it 'handles command errors gracefully' do
          post :command, params: { command: 'raise "test error"' }
          
          parsed_response = JSON.parse(response.body)
          expect(parsed_response).to have_key('error')
          expect(parsed_response['error']).to include('RuntimeError')
          expect(parsed_response['error']).to include('test error')
        end

        it 'resets stdout after execution' do
          original_stdout = $stdout
          post :command, params: { command: 'puts "test"' }
          expect($stdout).to eq(original_stdout)
        end

        it 'resets stdout even when error occurs' do
          original_stdout = $stdout
          post :command, params: { command: 'raise "error"' }
          expect($stdout).to eq(original_stdout)
        end
      end

      context 'when console tool is disabled' do
        before do
          allow(Rails.application.config.llama_bot_rails).to receive(:enable_console_tool).and_return(false)
        end

        it 'returns forbidden status' do
          post :command, params: { command: command }
          
          expect(response).to have_http_status(:forbidden)
          parsed_response = JSON.parse(response.body)
          expect(parsed_response['error']).to eq('Console tool is disabled')
        end
      end
    end

    context 'without valid agent authentication' do
      it 'rejects the request' do
        post :command, params: { command: command }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with invalid token' do
      before do
        request.headers['Authorization'] = 'LlamaBot invalid-token'
      end

      it 'rejects the request' do
        post :command, params: { command: command }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #send_message' do
    let(:message_params) do
      {
        message: 'Test message',
        thread_id: 'test-thread-123'
      }
    end

    before do
      # Mock the LlamaBot backend
      allow(LlamaBotRails::LlamaBot).to receive(:send_agent_message) do |state_payload, &block|
        # Simulate streaming response
        if block_given?
          block.call({ type: 'start', content: 'Starting...' })
          block.call({ type: 'ai', content: 'Test response' })
          block.call({ type: 'final', content: 'Done' })
        end
      end
    end

    it 'streams the agent response' do
      post :send_message, params: message_params
      
      expect(response).to be_successful
      expect(response.headers['Content-Type']).to include('text/event-stream')
      expect(response.headers['Cache-Control']).to eq('no-cache')
      expect(response.headers['Connection']).to eq('keep-alive')
    end

    it 'includes user_id in the generated token' do
      expect(Rails.application.message_verifier(:llamabot_ws)).to receive(:generate) do |payload, options|
        expect(payload[:user_id]).to eq(123)
        expect(options[:expires_in]).to eq(30.minutes)
        'generated-token'
      end

      post :send_message, params: message_params
    end

    it 'builds state payload with correct parameters' do
      expect_any_instance_of(LlamaBotRails::AgentStateBuilder).to receive(:build).and_call_original
      
      post :send_message, params: message_params
    end

    it 'handles backend errors gracefully' do
      allow(LlamaBotRails::LlamaBot).to receive(:send_agent_message).and_raise(StandardError.new('Backend error'))
      
      post :send_message, params: message_params
      
      expect(response).to be_successful
      # Response should contain error in SSE format
    end
  end

  describe 'GET #threads' do
    before do
      allow(LlamaBotRails::LlamaBot).to receive(:get_threads).and_return([
        { id: 'thread-1', title: 'Test Thread 1' },
        { id: 'thread-2', title: 'Test Thread 2' }
      ])
    end

    it 'returns list of threads' do
      get :threads
      
      expect(response).to be_successful
      threads = JSON.parse(response.body)
      expect(threads).to be_an(Array)
      expect(threads.length).to eq(2)
    end

    it 'handles backend errors' do
      allow(LlamaBotRails::LlamaBot).to receive(:get_threads).and_raise(StandardError.new('Backend error'))
      
      get :threads
      
      expect(response).to have_http_status(:internal_server_error)
      error_response = JSON.parse(response.body)
      expect(error_response['error']).to eq('Failed to fetch threads')
    end
  end

  describe 'GET #chat_history' do
    let(:thread_id) { 'test-thread-123' }

    before do
      allow(LlamaBotRails::LlamaBot).to receive(:get_chat_history).with(thread_id).and_return([
        { role: 'user', content: 'Hello' },
        { role: 'assistant', content: 'Hi there!' }
      ])
    end

    it 'returns chat history for valid thread' do
      get :chat_history, params: { thread_id: thread_id }
      
      expect(response).to be_successful
      history = JSON.parse(response.body)
      expect(history).to be_an(Array)
      expect(history.length).to eq(2)
    end

    it 'returns empty array for undefined thread_id' do
      get :chat_history, params: { thread_id: 'undefined' }
      
      expect(response).to be_successful
      history = JSON.parse(response.body)
      expect(history).to eq([])
    end

    it 'returns empty array for blank thread_id' do
      get :chat_history, params: { thread_id: '' }
      
      expect(response).to be_successful
      history = JSON.parse(response.body)
      expect(history).to eq([])
    end

    it 'handles backend errors' do
      allow(LlamaBotRails::LlamaBot).to receive(:get_chat_history).and_raise(StandardError.new('Backend error'))
      
      get :chat_history, params: { thread_id: thread_id }
      
      expect(response).to have_http_status(:internal_server_error)
      error_response = JSON.parse(response.body)
      expect(error_response['error']).to eq('Failed to fetch chat history')
    end
  end

  describe 'authentication integration' do
    context 'with check_agent_authentication before_action' do
      it 'allows requests with valid tokens to whitelisted actions' do
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
        allow(Rails.application.config.llama_bot_rails).to receive(:enable_console_tool).and_return(true)
        
        post :command, params: { command: 'puts "test"' }
        expect(response).to be_successful
      end

      it 'rejects requests without tokens to actions requiring authentication' do
        post :command, params: { command: 'puts "test"' }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with user resolution' do
      it 'resolves current user during send_message' do
        expect(LlamaBotRails.current_user_resolver).to receive(:call).with(request.env).and_return(mock_user)
        
        post :send_message, params: { message: 'test', thread_id: 'thread-1' }
        expect(response).to be_successful
      end

      it 'includes resolved user id in token payload' do
        expect(Rails.application.message_verifier(:llamabot_ws)).to receive(:generate).with(
          hash_including(user_id: 123),
          expires_in: 30.minutes
        )
        
        post :send_message, params: { message: 'test', thread_id: 'thread-1' }
      end
    end
  end

  describe '#safety_eval' do
    let(:controller_instance) { described_class.new }

    before do
      allow(Rails.application.config.llama_bot_rails).to receive(:enable_console_tool).and_return(true)
    end

    it 'evaluates code in Rails root context' do
      result = controller_instance.send(:safety_eval, 'Dir.pwd')
      expect(result).to eq(Rails.root.to_s)
    end

    it 'raises exceptions from evaluated code' do
      expect {
        controller_instance.send(:safety_eval, 'raise "test error"')
      }.to raise_error(RuntimeError, 'test error')
    end

    it 'logs the input being evaluated' do
      expect(Rails.logger).to receive(:info).with('[[LlamaBot]] Evaluating input: 1 + 1')
      controller_instance.send(:safety_eval, '1 + 1')
    end

    it 'logs errors that occur during evaluation' do
      expect(Rails.logger).to receive(:info).with('[[LlamaBot]] Evaluating input: raise "test"')
      expect(Rails.logger).to receive(:error).with('Error in safety_eval: test')
      
      expect {
        controller_instance.send(:safety_eval, 'raise "test"')
      }.to raise_error(RuntimeError)
    end
  end
end
