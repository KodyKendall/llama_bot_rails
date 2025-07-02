require 'rails_helper'
require 'llama_bot_rails/llama_bot'

RSpec.describe LlamaBotRails::LlamaBot do

  describe '.send_agent_message' do
    it 'sends an agent message' do
      result = described_class.send_agent_message(message: 'Hello', thread_id: '123')
      expect(result).to be_a(Enumerator)
    end
  end

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

    let(:ai_response) do
      {
        "content" => "Hello! I see your test message. How can I help?",
        "type" => "ai",
        "id" => "run--test-123"
      }
    end

    let(:final_response) do
      {
        "type" => "final",
        "node" => "final",
        "value" => "final",
        "messages" => []
      }
    end

    # Mock HTTP response that simulates FastAPI streaming response
    let(:streaming_response_body) do
      "#{ai_response.to_json}\n#{final_response.to_json}\n"
    end

    let(:concatenated_response_body) do
      # Simulate response without proper newlines (the problematic case)
      "#{ai_response.to_json}#{final_response.to_json}"
    end

    context 'when called with a block (streaming behavior)' do
      before do
        # Mock the HTTP streaming behavior
        mock_http = double('http')
        mock_request = double('request')
        mock_response = double('response')

        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
        allow(mock_request).to receive(:[]=)
        allow(mock_request).to receive(:body=)

        allow(mock_http).to receive(:request).and_yield(mock_response)
        allow(mock_response).to receive(:code).and_return(200)
        allow(mock_response).to receive(:read_body).and_yield(streaming_response_body)
      end

      it 'yields each parsed JSON chunk' do
        yielded_chunks = []
        described_class.send_agent_message(message, thread_id) do |chunk|
          yielded_chunks << chunk
        end

        expect(yielded_chunks).to include(ai_response)
        expect(yielded_chunks).to include(final_response)
        expect(yielded_chunks.length).to eq(2)
      end

      it 'sends correct HTTP request' do
        expect(Net::HTTP).to receive(:new).with('localhost', 8000)
        expect(Net::HTTP::Post).to receive(:new).with(instance_of(URI::HTTP))

        described_class.send_agent_message(message, thread_id) { |chunk| }
      end

      it 'sets correct headers' do
        mock_request = double('request')
        allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
        expect(mock_request).to receive(:[]=).with('Content-Type', 'application/json')
        expect(mock_request).to receive(:body=).with(
          { message: message, thread_id: thread_id }.to_json
        )

        # Mock the rest of the HTTP call
        mock_http = double('http')
        mock_response = double('response')
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:request).and_yield(mock_response)
        allow(mock_response).to receive(:code).and_return(200)
        allow(mock_response).to receive(:read_body)

        described_class.send_agent_message(message, thread_id) { |chunk| }
      end
    end

    context 'when called without a block (enum_for behavior)' do
      before do
        # Mock successful HTTP response
        mock_http = double('http')
        mock_request = double('request')
        mock_response = double('response')

        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
        allow(mock_request).to receive(:[]=)
        allow(mock_request).to receive(:body=)
        allow(mock_http).to receive(:request).and_yield(mock_response)
        allow(mock_response).to receive(:code).and_return(200)
        allow(mock_response).to receive(:read_body).and_yield(streaming_response_body)
      end

      it 'returns an Enumerator' do
        result = described_class.send_agent_message(message, thread_id)
        expect(result).to be_an(Enumerator)
      end

      it 'enumerator yields the same chunks as block version' do
        enumerator = described_class.send_agent_message(message, thread_id)
        chunks = enumerator.to_a

        expect(chunks).to include(ai_response)
        expect(chunks).to include(final_response)
        expect(chunks.length).to eq(2)
      end
    end

    context 'when parsing concatenated JSON (no newlines)' do
      before do
        # Mock HTTP response with concatenated JSON (problematic case)
        mock_http = double('http')
        mock_request = double('request')
        mock_response = double('response')

        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
        allow(mock_request).to receive(:[]=)
        allow(mock_request).to receive(:body=)
        allow(mock_http).to receive(:request).and_yield(mock_response)
        allow(mock_response).to receive(:code).and_return(200)
        
        # Simulate chunked reading of concatenated JSON - the real issue we're testing
        # Split the concatenated response to simulate how it might come in chunks
        allow(mock_response).to receive(:read_body) do |&block|
          block.call("#{ai_response.to_json}#{final_response.to_json}")
        end
      end

      it 'logs parse error when JSON objects are concatenated without newlines' do
        expect(Rails.logger).to receive(:error).with(/Final buffer parse error/)
        
        yielded_chunks = []
        described_class.send_agent_message(message, thread_id) do |chunk|
          yielded_chunks << chunk
        end

        # Concatenated JSON without newlines fails to parse, so no chunks are yielded
        expect(yielded_chunks).to be_empty
      end
    end

    context 'when JSON parsing fails' do
      let(:invalid_json_response) { "invalid json\n{\"valid\": \"json\"}\n" }

      before do
        mock_http = double('http')
        mock_request = double('request')
        mock_response = double('response')

        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
        allow(mock_request).to receive(:[]=)
        allow(mock_request).to receive(:body=)
        allow(mock_http).to receive(:request).and_yield(mock_response)
        allow(mock_response).to receive(:code).and_return(200)
        allow(mock_response).to receive(:read_body).and_yield(invalid_json_response)
      end

      it 'logs parse errors and continues processing valid JSON' do
        expect(Rails.logger).to receive(:error).with(/Parse error/)

        yielded_chunks = []
        described_class.send_agent_message(message, thread_id) do |chunk|
          yielded_chunks << chunk
        end

        expect(yielded_chunks).to include({"valid" => "json"})
      end
    end

    context 'when HTTP request fails' do
      before do
        allow(Net::HTTP).to receive(:new).and_raise(SocketError.new("Connection refused"))
      end

      it 'returns an Enumerator when called without block (error during enumeration)' do
        result = described_class.send_agent_message(message, thread_id)
        expect(result).to be_an(Enumerator)
        
        # The error happens when we try to iterate
        expect(Rails.logger).to receive(:error).with("Error sending agent message: Connection refused")
        expect { result.to_a }.not_to raise_error
      end

      it 'yields no chunks when called with block and error occurs' do
        expect(Rails.logger).to receive(:error).with("Error sending agent message: Connection refused")
        
        yielded_chunks = []
        result = described_class.send_agent_message(message, thread_id) do |chunk|
          yielded_chunks << chunk
        end
        
        expect(yielded_chunks).to be_empty
        expect(result).to eq({ error: "Connection refused" })
      end
    end

    context 'when HTTP response has error status' do
      before do
        mock_http = double('http')
        mock_request = double('request')
        mock_response = double('response')

        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
        allow(mock_request).to receive(:[]=)
        allow(mock_request).to receive(:body=)
        allow(mock_http).to receive(:request).and_yield(mock_response)
        allow(mock_response).to receive(:code).and_return(500)
        allow(mock_response).to receive(:body).and_return("Internal Server Error")
      end

      it 'does not yield any chunks for error responses' do
        yielded_chunks = []
        described_class.send_agent_message(message, thread_id) do |chunk|
          yielded_chunks << chunk
        end

        expect(yielded_chunks).to be_empty
      end
    end

    context 'when request body contains only message' do
      before do
        mock_http = double('http')
        mock_request = double('request')
        mock_response = double('response')

        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
        allow(mock_request).to receive(:[]=)
        allow(mock_response).to receive(:code).and_return(200)
        allow(mock_response).to receive(:read_body)
        allow(mock_http).to receive(:request).and_yield(mock_response)

        expect(mock_request).to receive(:body=).with(
          { message: message, thread_id: nil }.to_json
        )
      end

      it 'sends minimal request body when optional params are nil' do
        described_class.send_agent_message(message) { |chunk| }
      end
    end

    context 'with edge cases in streaming response' do
      let(:empty_response) { "" }
      let(:whitespace_response) { "   \n  \n  " }

      before do
        mock_http = double('http')
        mock_request = double('request')
        @mock_response = double('response')

        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
        allow(mock_request).to receive(:[]=)
        allow(mock_request).to receive(:body=)
        allow(mock_http).to receive(:request).and_yield(@mock_response)
        allow(@mock_response).to receive(:code).and_return(200)
      end

      it 'handles empty response gracefully' do
        allow(@mock_response).to receive(:read_body).and_yield(empty_response)

        yielded_chunks = []
        expect {
          described_class.send_agent_message(message, thread_id) do |chunk|
            yielded_chunks << chunk
          end
        }.not_to raise_error

        expect(yielded_chunks).to be_empty
      end

      it 'handles whitespace-only response gracefully' do
        allow(@mock_response).to receive(:read_body).and_yield(whitespace_response)

        yielded_chunks = []
        expect {
          described_class.send_agent_message(message, thread_id) do |chunk|
            yielded_chunks << chunk
          end
        }.not_to raise_error

        expect(yielded_chunks).to be_empty
      end
    end
  end
end 