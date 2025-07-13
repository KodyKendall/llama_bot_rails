require 'rails_helper'

RSpec.describe LlamaBotRails::AgentController, type: :controller do
  routes { LlamaBotRails::Engine.routes }

  describe 'POST #send_message' do
    let(:params_hash) do
      {
        message:   message,
        thread_id: thread_id,
        agent_name: 'llamabot',
        agent_prompt: 'You are LlamaBot, a helpful assistant.',
        api_token: 'token-123'
      }
    end

    before do
      @request.headers['Content-Type']     = 'application/json'
      @request.headers['Accept']           = 'text/event-stream'
      @request.headers['Accept-Encoding']  = 'identity'
    end

    let(:message) { 'Test message' }
    let(:thread_id) { '2025-06-28_10-06-33' }
    let(:agent_name) { 'test_agent' }

    let(:ai_chunk) do
      {
        "content" => "Hello! I see your test message. How can I help?",
        "type" => "ai",
        "id" => "run--test-123"
      }
    end

    let(:final_chunk) do
      {
        "type" => "final",
        "node" => "final", 
        "value" => "final",
        "messages" => []
      }
    end

    before do
      # Note: send_message action doesn't require authentication
    end

    context 'when streaming succeeds' do
      before do
        # Mock LlamaBot.send_agent_message to yield chunks as expected
        allow(LlamaBotRails::LlamaBot).to receive(:send_agent_message).and_yield(ai_chunk).and_yield(final_chunk)
      end

      it 'sets proper SSE headers' do
        post :send_message, body: params_hash.to_json
        expect(response.headers['Content-Type']).to eq('text/event-stream')
      end

      it 'calls LlamaBot.send_agent_message with correct parameters' do
        expect(LlamaBotRails::LlamaBot).to receive(:send_agent_message)
          .with(hash_including(message: message, thread_id: thread_id))
          .and_yield(ai_chunk).and_yield(final_chunk)

        post :send_message, body: params_hash.to_json
      end

      it 'responds with success status' do
        post :send_message, body: params_hash.to_json
        expect(response).to be_successful
      end
    end

    context 'when LlamaBot raises an error' do
      let(:error_message) { 'Connection failed' }

      before do
        allow(LlamaBotRails::LlamaBot).to receive(:send_agent_message)
          .and_raise(StandardError.new(error_message))
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error)
          .with("Error in send_message action: #{error_message}")

        post :send_message, body: params_hash.to_json
      end

      it 'still responds successfully (error is handled gracefully)' do
        post :send_message, body: params_hash.to_json
        expect(response).to be_successful
      end
    end

    context 'with missing parameters' do
      let(:message)   { 'Hi' }
      let(:thread_id) { nil  }

      it 'calls LlamaBot with nil thread_id when not provided' do
        expect(LlamaBotRails::LlamaBot).to receive(:send_agent_message)
          .with(hash_including(message: message, thread_id: nil))

        post :send_message, body: { message: message }.to_json
      end
    end

    context 'with invalid JSON in chunks' do
      let(:invalid_chunk) { "invalid json string" }

      before do
        allow(LlamaBotRails::LlamaBot).to receive(:send_agent_message)
          .and_yield(invalid_chunk)
      end

      it 'handles invalid JSON gracefully' do
        expect {
          post :send_message, body: params_hash.to_json
        }.not_to raise_error
      end
    end

    context 'when testing streaming behavior (integration-style)' do
      it 'is designed to work with ActionController::Live streaming' do
        # This test verifies the controller is set up for streaming
        expect(controller.class.ancestors).to include(ActionController::Live)
      end

      it 'uses the send_agent_message method with a block for streaming' do
        # This test verifies we call the streaming method correctly
        expect(LlamaBotRails::LlamaBot).to receive(:send_agent_message) do |agent_params, &block|
          expect(block).to be_present  # Verify a block is passed
          expect(agent_params).to include(message: message)
          expect(agent_params[:thread_id]).to eq(thread_id) if agent_params.key?(:thread_id)
        end

        post :send_message, body: params_hash.to_json
      end
    end
  end

  describe 'other actions' do
    describe 'GET #chat' do
      it 'renders successfully' do
        get :chat
        expect(response).to be_successful
      end
    end

    describe 'GET #threads' do
      before do
        allow(LlamaBotRails::LlamaBot).to receive(:get_threads)
          .and_return([{ 'id' => 'thread1', 'name' => 'Test Thread' }])
      end

      it 'returns threads as JSON' do
        get :threads
        expect(response).to be_successful
        expect(response.content_type).to include('application/json')
      end

      it 'calls LlamaBot.get_threads' do
        expect(LlamaBotRails::LlamaBot).to receive(:get_threads)
        get :threads
      end
    end

    describe 'GET #chat_history' do
      let(:thread_id) { 'test_thread_123' }

      before do
        allow(LlamaBotRails::LlamaBot).to receive(:get_chat_history)
          .with(thread_id)
          .and_return([{ 'role' => 'user', 'content' => 'Hello' }])
      end

      it 'returns chat history as JSON' do
        get :chat_history, params: { thread_id: thread_id }
        expect(response).to be_successful
        expect(response.content_type).to include('application/json')
      end

      it 'calls LlamaBot.get_chat_history with correct thread_id' do
        expect(LlamaBotRails::LlamaBot).to receive(:get_chat_history).with(thread_id)
        get :chat_history, params: { thread_id: thread_id }
      end

      it 'handles undefined thread_id gracefully' do
        get :chat_history, params: { thread_id: 'undefined' }
        expect(response).to be_successful
        expect(JSON.parse(response.body)).to eq([])
      end
    end
  end

  describe 'POST /llama_bot/agent/send_message (SSE)' do
    it 'streams SSE events as they are produced' do
      ai_chunk    = { 'role' => 'assistant', 'content' => 'Hi' }
      final_chunk = { 'type' => 'final', 'content' => 'final' }

      allow(LlamaBotRails::LlamaBot).to receive(:send_agent_message)
        .and_yield(ai_chunk).and_yield(final_chunk)

      post :send_message,
           body:  { message: 'hello' }.to_json,
           as:    :json               # rails-6 controller spec helper

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/event-stream')

      events = response.body.split("\n\n").map { |e| e.sub(/^data:\s*/, '') }
      expect(events.first).to include('assistant')
      expect(events.last ).to include('"type":"final"')
    end
  end

  describe 'POST #command' do
    let(:valid_token) { Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test'}) }
    let(:command) { 'puts "Hello World"' }
    
    context 'with valid authentication' do
      before do
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
      end
      
      it 'executes the command successfully' do
        post :command, params: { command: command }
        expect(response).to have_http_status(:success)
        
        result = JSON.parse(response.body)
        expect(result).to have_key('output')
        expect(result).to have_key('result')
      end
      
      it 'handles command execution errors' do
        post :command, params: { command: 'raise "Test error"' }
        expect(response).to have_http_status(:success)
        
        result = JSON.parse(response.body)
        expect(result).to have_key('error')
        expect(result['error']).to include('Test error')
      end
    end
    
    context 'with invalid authentication' do
      before do
        request.headers['Authorization'] = 'LlamaBot invalid-token'
      end
      
      it 'returns unauthorized' do
        post :command, params: { command: command }
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'with missing authentication' do
      it 'returns unauthorized' do
        post :command, params: { command: command }
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'with expired token' do
      let(:expired_token) do
        Rails.application.message_verifier(:llamabot_ws).generate(
          {session_id: 'test'}, 
          expires_in: -1.minute
        )
      end
      
      before do
        request.headers['Authorization'] = "LlamaBot #{expired_token}"
      end
      
      it 'returns unauthorized' do
        post :command, params: { command: command }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'AgentAuth integration' do
    it 'includes AgentAuth module' do
      expect(controller.class.ancestors).to include(LlamaBotRails::AgentAuth)
    end
    
    it 'responds to llama_bot_request?' do
      expect(controller).to respond_to(:llama_bot_request?)
    end
    
    it 'has authenticate_user_or_agent! filter on command action' do
      filters = controller.class._process_action_callbacks.select do |callback|
        callback.filter == :authenticate_user_or_agent! && callback.kind == :before
      end
      
      expect(filters).not_to be_empty
    end
  end
end
