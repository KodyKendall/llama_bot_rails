require 'rails_helper'

RSpec.describe LlamaBotRails::LlamaBot do
  let(:api_url) { "http://localhost:8000" }
  let(:http) { instance_double(Net::HTTP) }
  let(:response) { instance_double(Net::HTTPResponse) }
  let(:agent_params) { { message: "test message" } }

  # Configure shared stubs for all tests in this block
  before do
    allow(Rails.application.config.llama_bot_rails).to receive(:llamabot_api_url).and_return(api_url)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=) # This is the key fix
    allow(http).to receive(:request).and_yield(response)
    allow(response).to receive(:code).and_return("200")
  end
  
  describe ".get_threads" do
    before do
      allow(Net::HTTP).to receive(:get_response).and_return(response)
      allow(response).to receive(:body).and_return('{"threads": ["thread1"]}')
    end
    
    it "returns list of threads" do
      expect(described_class.get_threads).to eq({ "threads" => ["thread1"] })
    end

    context "when backend returns an error" do
      before do
        allow(Net::HTTP).to receive(:get_response).and_raise(StandardError.new("backend error"))
        allow(Rails.logger).to receive(:error)
      end

      it "handles backend errors" do
        expect(described_class.get_threads).to eq([])
        expect(Rails.logger).to have_received(:error).with("Error fetching threads: backend error")
      end
    end
  end

  describe ".get_chat_history" do
    let(:thread_id) { "123" }

    before do
      allow(Net::HTTP).to receive(:get_response).and_return(response)
      allow(response).to receive(:body).and_return('{"history": ["message1"]}')
    end

    it "returns chat history" do
      expect(described_class.get_chat_history(thread_id)).to eq({ "history" => ["message1"] })
    end
    
    context "when backend returns an error" do
      before do
        allow(Net::HTTP).to receive(:get_response).and_raise(StandardError.new("backend error"))
        allow(Rails.logger).to receive(:error)
      end

      it "handles backend errors gracefully" do
        expect(described_class.get_chat_history(thread_id)).to eq([])
        expect(Rails.logger).to have_received(:error).with("Error fetching chat history: backend error")
      end
    end
  end
  
  describe ".send_agent_message" do
    context "when called with a block (streaming behavior)" do
      before do
        allow(response).to receive(:read_body).and_yield('{"message": "chunk1"}' + "\n").and_yield('{"message": "chunk2"}' + "\n")
      end

      it "yields each parsed JSON chunk" do
        results = []
        described_class.send_agent_message(agent_params) { |chunk| results << chunk }
        expect(results).to eq([{ "message" => "chunk1" }, { "message" => "chunk2" }])
      end

      it "sends correct HTTP request" do
        request = instance_double(Net::HTTP::Post)
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)

        expect(Net::HTTP).to receive(:new).with("localhost", 8000).and_return(http)
        described_class.send_agent_message(agent_params) {}
      end
      
      it "sets correct headers" do
        request = instance_double(Net::HTTP::Post)
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:body=)

        expect(request).to receive(:[]=).with('Content-Type', 'application/json')
        described_class.send_agent_message(agent_params) {}
      end
    end

    context "when called without a block (enum_for behavior)" do
      let(:stream_chunks) { ['{"message": "chunk1"}' + "\n", '{"message": "chunk2"}' + "\n"] }

      before do
        allow(response).to receive(:read_body) do |&block|
          stream_chunks.each { |chunk| block.call(chunk) }
        end
      end

      it "enumerator yields the same chunks as block version" do
        block_results = []
        described_class.send_agent_message(agent_params) { |chunk| block_results << chunk }

        enum = described_class.send_agent_message(agent_params)
        enum_results = enum.to_a
        
        expect(enum_results).to eq(block_results)
      end
    end

    context "when parsing concatenated JSON (no newlines)" do
      let(:concatenated_json) { '{"message": "chunk1"}{"message": "chunk2"}' }
      
      before do
        allow(Rails.logger).to receive(:error)
        allow(response).to receive(:read_body).and_yield(concatenated_json)
      end

      it "logs parse error when JSON objects are concatenated without newlines" do
        described_class.send_agent_message(agent_params) { |chunk| }
        expect(Rails.logger).to have_received(:error).with(/Final buffer parse error/)
      end
    end

    context "when JSON parsing fails" do
      let(:stream_data) { ['{"message": "chunk1"}' + "\n", 'not-json' + "\n", '{"message": "chunk2"}' + "\n"] }
      
      before do
        allow(Rails.logger).to receive(:error)
        allow(response).to receive(:read_body) do |&block|
          stream_data.each { |chunk| block.call(chunk) }
        end
      end

      it "logs parse errors and continues processing valid JSON" do
        results = []
        described_class.send_agent_message(agent_params) { |chunk| results << chunk }
        
        expect(results).to eq([{ "message" => "chunk1" }, { "message" => "chunk2" }])
        # Update the expectation to match the actual error message from the JSON parser
        expect(Rails.logger).to have_received(:error).with("Parse error: unexpected token 'not-json' at line 1 column 1")
      end
    end

    context "when HTTP response has error status" do
      before do
        allow(response).to receive(:code).and_return("500")
        allow(response).to receive(:body).and_return("Server Error")
      end

      it "does not yield any chunks for error responses" do
        results = []
        described_class.send_agent_message(agent_params) { |chunk| results << chunk }
        expect(results).to be_empty
      end
    end

    context "when request body contains only message" do
      let(:agent_params) { { message: "test message", thread_id: nil, other_param: nil } }
      let(:expected_body) { { message: "test message", thread_id: nil, other_param: nil }.to_json }
      let(:request) { instance_double(Net::HTTP::Post, "[]=": true, :body= => nil) }

      before do
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(response).to receive(:read_body)
      end

      it "sends minimal request body when optional params are nil" do
        expect(request).to receive(:body=).with(expected_body)
        described_class.send_agent_message(agent_params) {}
      end
    end

    context "with edge cases in streaming response" do
      it "handles empty response gracefully" do
        allow(response).to receive(:read_body) # Yields nothing
        expect { |b| described_class.send_agent_message(agent_params, &b) }.not_to yield_control
      end

      it "handles whitespace-only response gracefully" do
        allow(response).to receive(:read_body).and_yield("   \n   ")
        allow(Rails.logger).to receive(:error)
        expect { |b| described_class.send_agent_message(agent_params, &b) }.not_to yield_control
        expect(Rails.logger).not_to have_received(:error)
      end
    end
  end
end 