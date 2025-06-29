require 'rails_helper'
require 'net/http'
require 'json'
require 'time'
require 'llama_bot_rails/llama_bot'

RSpec.describe 'Agent streaming', type: :request do
  include Rails.application.routes.url_helpers

  # Capybara already starts a Puma server for the dummy app.
  before(:all) do
    Capybara.server = :puma, { Silent: true }
  end

  it 'flushes each SSE chunk as soon as it is written' do
    # --- stub the LlamaBot call so we control timing -------------------
    first_chunk  = { step: 1 }
    second_chunk = { step: 2 }

    allow(LlamaBotRails::LlamaBot).to receive(:send_agent_message) do |_params, &blk|
      blk.call(first_chunk)
      sleep 0.25                     # simulate work – proves async flush
      blk.call(second_chunk)
    end
    # ------------------------------------------------------------------

    # Spin up a lightweight Rack server for the Rails app
    server = Capybara::Server.new(Rails.application, port: Capybara.server_port || 9887)
    server.boot

    uri = URI("http://#{server.host}:#{server.port}/llama_bot/agent/send_message")

    req = Net::HTTP::Post.new(uri)
    req['Accept']        = 'text/event-stream'
    req['Content-Type']  = 'application/json'
    req['Accept-Encoding'] = 'identity'
    req.body = { message: 'hi' }.to_json

    arrival_times = []
    chunks        = []

    Net::HTTP.start(uri.host, uri.port) do |http|
      http.request(req) do |res|
        expect(res.code.to_i).to eq(200)
        expect(res['Content-Type']).to eq('text/event-stream')

        res.read_timeout = 2 # seconds
        res.read_body do |chunk|
          arrival_times << Time.now
          chunks        << chunk.dup
          break if chunks.size == 2
        end
      end
    end

    # We received exactly the two chunks the stub emitted
    expect(chunks.first).to include(first_chunk.to_json)
    expect(chunks.last ).to include(second_chunk.to_json)

    # And they arrived at least 0.2 s apart ⇒ streamed, not buffered
    delta = arrival_times[1] - arrival_times[0]
    expect(delta).to be > 0.2
  end
end 