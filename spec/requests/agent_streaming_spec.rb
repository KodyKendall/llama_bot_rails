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

  it 'sends multiple SSE events with proper formatting' do
    # --- stub the LlamaBot call so we control the output ---------------
    first_chunk  = { step: 1, content: 'First message' }
    second_chunk = { step: 2, content: 'Second message' }

    allow(LlamaBotRails::LlamaBot).to receive(:send_agent_message) do |_params, &blk|
      blk.call(first_chunk)
      blk.call(second_chunk)
    end
    # ------------------------------------------------------------------

    # Spin up a lightweight Rack server for the Rails app
    server = Capybara::Server.new(Rails.application, port: Capybara.server_port || 9887)
    server.boot

    uri = URI("http://#{server.host}:#{server.port}/llama_bot_rails/agent/send_message")

    req = Net::HTTP::Post.new(uri)
    req['Accept']        = 'text/event-stream'
    req['Content-Type']  = 'application/json'
    req['Accept-Encoding'] = 'identity'
    req.body = { message: 'hi' }.to_json

    response_body = ''

    Net::HTTP.start(uri.host, uri.port) do |http|
      http.read_timeout = 2 # seconds
      http.request(req) do |res|
        expect(res.code.to_i).to eq(200)
        expect(res['Content-Type']).to eq('text/event-stream')

        res.read_body do |chunk|
          response_body += chunk
        end
      end
    end

    # Parse the SSE events
    events = response_body.split("\n\n").reject(&:blank?)

    # We should have received exactly two SSE events
    expect(events.size).to eq(2), "Expected 2 SSE events, got #{events.size}"

    # Each event should start with "data:" and contain the expected JSON
    first_event = events[0].sub(/^data:\s*/, '')
    second_event = events[1].sub(/^data:\s*/, '')

    expect(first_event).to include(first_chunk.to_json)
    expect(second_event).to include(second_chunk.to_json)
  end
end 