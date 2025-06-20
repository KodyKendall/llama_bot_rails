require 'rails_helper'
require 'llama_bot_rails/llama_bot'

RSpec.describe LlamaBotRails::LlamaBot do
  describe '.get_threads' do
    context 'when the request is successful' do
      before do
        stub_request(:get, "http://localhost:8000/threads")
          .to_return(
            status: 200,
            body: [{ id: 'thread1', name: 'Test Thread' }].to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns parsed JSON response' do
        result = described_class.get_threads
        expect(result).to eq([{ 'id' => 'thread1', 'name' => 'Test Thread' }])
      end
    end

    context 'when the request fails' do
      before do
        stub_request(:get, "http://localhost:8000/threads")
          .to_raise(StandardError.new("Connection failed"))
      end

      it 'logs the error and returns empty array' do
        expect(Rails.logger).to receive(:error).with("Error fetching threads: Connection failed")
        result = described_class.get_threads
        expect(result).to eq([])
      end
    end

    context 'when the response is invalid JSON' do
      before do
        stub_request(:get, "http://localhost:8000/threads")
          .to_return(status: 200, body: "invalid json")
      end

      it 'logs the error and returns empty array' do
        expect(Rails.logger).to receive(:error).with(/Error fetching threads/)
        result = described_class.get_threads
        expect(result).to eq([])
      end
    end
  end

  describe '.get_chat_history' do
    let(:thread_id) { 'test_thread_123' }

    context 'when the request is successful' do
      before do
        stub_request(:get, "http://localhost:8000/chat-history/#{thread_id}")
          .to_return(
            status: 200,
            body: [
              { role: 'user', content: 'Hello' },
              { role: 'assistant', content: 'Hi there!' }
            ].to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns parsed JSON response' do
        result = described_class.get_chat_history(thread_id)
        expect(result).to eq([
          { 'role' => 'user', 'content' => 'Hello' },
          { 'role' => 'assistant', 'content' => 'Hi there!' }
        ])
      end
    end

    context 'when the request fails' do
      before do
        stub_request(:get, "http://localhost:8000/chat-history/#{thread_id}")
          .to_raise(SocketError.new("Failed to connect"))
      end

      it 'logs the error and returns empty array' do
        expect(Rails.logger).to receive(:error).with("Error fetching chat history: Failed to connect")
        result = described_class.get_chat_history(thread_id)
        expect(result).to eq([])
      end
    end
  end

  describe '.send_agent_message' do
    let(:message) { 'Test message' }
    let(:thread_id) { 'test_thread_456' }
    let(:agent_name) { 'test_agent' }

    context 'when the request is successful' do
      before do
        stub_request(:post, "http://localhost:8000/llamabot-chat-message")
          .with(
            body: {
              message: message,
              thread_id: thread_id,
              agent: agent_name
            }.to_json
          )
          .to_return(
            status: 200,
            body: { status: 'success', message_id: '123' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'sends the correct payload and returns parsed response' do
        result = described_class.send_agent_message(message, thread_id, agent_name)
        expect(result).to eq({ 'status' => 'success', 'message_id' => '123' })
      end
    end

    context 'when called with minimal parameters' do
      before do
        stub_request(:post, "http://localhost:8000/llamabot-chat-message")
          .with(
            body: {
              message: message,
              thread_id: nil,
              agent: nil
            }.to_json
          )
          .to_return(
            status: 200,
            body: { status: 'success' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'sends message with nil values for optional parameters' do
        result = described_class.send_agent_message(message)
        expect(result).to eq({ 'status' => 'success' })
      end
    end

    context 'when the request fails' do
      before do
        stub_request(:post, "http://localhost:8000/llamabot-chat-message")
          .to_raise(Timeout::Error.new("Request timeout"))
      end

      it 'logs the error and returns empty array' do
        expect(Rails.logger).to receive(:error).with("Error sending agent message: Request timeout")
        result = described_class.send_agent_message(message, thread_id, agent_name)
        expect(result).to eq([])
      end
    end

    context 'when the response is not valid JSON' do
      before do
        stub_request(:post, "http://localhost:8000/llamabot-chat-message")
          .to_return(status: 200, body: "Server Error")
      end

      it 'logs the error and returns empty array' do
        expect(Rails.logger).to receive(:error).with(/Error sending agent message/)
        result = described_class.send_agent_message(message, thread_id, agent_name)
        expect(result).to eq([])
      end
    end

    context 'when Net::HTTP.post raises an exception' do
      before do
        allow(Net::HTTP).to receive(:post).and_raise(Errno::ECONNREFUSED.new("Connection refused"))
      end

      it 'logs the error and returns empty array' do
        expect(Rails.logger).to receive(:error).with("Error sending agent message: Connection refused - Connection refused")
        result = described_class.send_agent_message(message)
        expect(result).to eq([])
      end
    end
  end
end 