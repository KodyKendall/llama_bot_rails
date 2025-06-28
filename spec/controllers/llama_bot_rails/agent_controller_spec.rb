require 'rails_helper'

RSpec.describe LlamaBotRails::AgentController, type: :controller do
  routes { LlamaBotRails::Engine.routes }

  describe 'POST #send_message' do
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
      # Mock the authentication if needed
      allow(controller).to receive(:authenticate_agent!).and_return(true)
    end

    context 'when streaming succeeds' do
      before do
        # Mock LlamaBot.send_agent_message to yield chunks as expected
        allow(LlamaBotRails::LlamaBot).to receive(:send_agent_message).and_yield(ai_chunk).and_yield(final_chunk)
      end

      it 'sets proper SSE headers' do
        post :send_message, params: { message: message, thread_id: thread_id }

        expect(response.headers['Content-Type']).to eq('text/event-stream')
        expect(response.headers['Cache-Control']).to eq('no-cache')
        expect(response.headers['Connection']).to eq('keep-alive')
      end

      it 'calls LlamaBot.send_agent_message with correct parameters' do
        expect(LlamaBotRails::LlamaBot).to receive(:send_agent_message)
          .with(message, thread_id)
          .and_yield(ai_chunk).and_yield(final_chunk)

        post :send_message, params: { message: message, thread_id: thread_id }
      end

      it 'responds with success status' do
        post :send_message, params: { message: message, thread_id: thread_id }
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

        post :send_message, params: { message: message, thread_id: thread_id }
      end

      it 'still responds successfully (error is handled gracefully)' do
        post :send_message, params: { message: message, thread_id: thread_id }
        expect(response).to be_successful
      end
    end

    context 'with missing parameters' do
      before do
        allow(LlamaBotRails::LlamaBot).to receive(:send_agent_message)
      end

      it 'handles nil message gracefully' do
        expect {
          post :send_message, params: { thread_id: thread_id }
        }.not_to raise_error
      end

      it 'handles nil thread_id gracefully' do
        expect {
          post :send_message, params: { message: message }
        }.not_to raise_error
      end

      it 'calls LlamaBot with nil thread_id when not provided' do
        expect(LlamaBotRails::LlamaBot).to receive(:send_agent_message)
          .with(message, nil)

        post :send_message, params: { message: message }
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
          post :send_message, params: { message: message, thread_id: thread_id }
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
        expect(LlamaBotRails::LlamaBot).to receive(:send_agent_message) do |msg, tid, &block|
          expect(block).to be_present  # Verify a block is passed
          expect(msg).to eq(message)
          expect(tid).to eq(thread_id)
        end

        post :send_message, params: { message: message, thread_id: thread_id }
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
end
