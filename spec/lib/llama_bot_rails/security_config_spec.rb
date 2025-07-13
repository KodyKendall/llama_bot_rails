require 'rails_helper'

RSpec.describe 'LlamaBotRails Security Configuration' do
  describe 'Global allowed_routes registry' do
    before do
      # Reset the global registry before each test
      LlamaBotRails.allowed_routes.clear
    end
    
    it 'initializes with empty Set' do
      expect(LlamaBotRails.allowed_routes).to be_a(Set)
      expect(LlamaBotRails.allowed_routes).to be_empty
    end
    
    it 'allows adding routes' do
      LlamaBotRails.allowed_routes << 'users#index'
      expect(LlamaBotRails.allowed_routes).to include('users#index')
    end
    
    it 'prevents duplicates' do
      LlamaBotRails.allowed_routes << 'users#index'
      LlamaBotRails.allowed_routes << 'users#index'
      expect(LlamaBotRails.allowed_routes.size).to eq(1)
    end
    
    it 'is accessible module-wide' do
      expect(LlamaBotRails.allowed_routes).to be_a(Set)
    end
  end
  
  describe 'Message verifier configuration' do
    it 'uses Rails message verifier with llamabot_ws key' do
      expect(Rails.application.message_verifier(:llamabot_ws)).to be_a(ActiveSupport::MessageVerifier)
    end
    
    it 'can generate and verify tokens' do
      token = Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test'})
      expect(token).to be_a(String)
      
      payload = Rails.application.message_verifier(:llamabot_ws).verify(token)
      expect(payload).to eq({session_id: 'test'})
    end
    
    it 'handles expired tokens' do
      token = Rails.application.message_verifier(:llamabot_ws).generate(
        {session_id: 'test'}, 
        expires_in: -1.minute
      )
      
      expect {
        Rails.application.message_verifier(:llamabot_ws).verify(token)
      }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
    end
    
    it 'handles invalid tokens' do
      expect {
        Rails.application.message_verifier(:llamabot_ws).verify('invalid-token')
      }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
    end
  end
  
  describe 'Engine configuration' do
    it 'has console tool enabled by default' do
      expect(Rails.configuration.llama_bot_rails.enable_console_tool).to be true
    end
    
    it 'has websocket_url configured' do
      expect(Rails.configuration.llama_bot_rails.websocket_url).to eq('ws://localhost:8000/ws')
    end
    
    it 'has llamabot_api_url configured' do
      expect(Rails.configuration.llama_bot_rails.llamabot_api_url).to eq('http://localhost:8000')
    end
  end
  
  describe 'Security token generation' do
    it 'generates unique tokens for each session' do
      token1 = Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test1'})
      token2 = Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test2'})
      
      expect(token1).not_to eq(token2)
    end
    
    it 'generates tokens with proper expiration' do
      token = Rails.application.message_verifier(:llamabot_ws).generate(
        {session_id: 'test'}, 
        expires_in: 30.minutes
      )
      
      payload = Rails.application.message_verifier(:llamabot_ws).verify(token)
      expect(payload).to eq({session_id: 'test'})
    end
    
    it 'validates token expiration' do
      # Token expires in 1 second
      token = Rails.application.message_verifier(:llamabot_ws).generate(
        {session_id: 'test'}, 
        expires_in: 1.second
      )
      
      # Should be valid immediately
      payload = Rails.application.message_verifier(:llamabot_ws).verify(token)
      expect(payload).to eq({session_id: 'test'})
      
      # Should be invalid after expiration (simulate time passing)
      expired_token = Rails.application.message_verifier(:llamabot_ws).generate(
        {session_id: 'test'}, 
        expires_in: -1.second
      )
      
      expect {
        Rails.application.message_verifier(:llamabot_ws).verify(expired_token)
      }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
    end
  end
  
  describe 'Auth scheme configuration' do
    it 'uses LlamaBot auth scheme' do
      expect(LlamaBotRails::AgentAuth::AUTH_SCHEME).to eq('LlamaBot')
    end
  end
  
  describe 'Security best practices' do
    it 'tokens are cryptographically secure' do
      token = Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test'})
      
      # Token should be long enough to be secure
      expect(token.length).to be > 40
      
      # Token should contain only safe characters
      expect(token).to match(/\A[A-Za-z0-9\-_=]+\z/)
    end
    
    it 'tokens are tamper-proof' do
      token = Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test'})
      
      # Modify the token slightly
      tampered_token = token.sub(/.$/, 'X')
      
      expect {
        Rails.application.message_verifier(:llamabot_ws).verify(tampered_token)
      }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
    end
    
    it 'different secret keys produce different tokens' do
      # This test verifies that tokens are dependent on the secret key
      original_secret = Rails.application.secret_key_base
      
      # Create verifier with original secret
      verifier1 = ActiveSupport::MessageVerifier.new(original_secret)
      token1 = verifier1.generate({session_id: 'test'})
      
      # Create verifier with different secret
      verifier2 = ActiveSupport::MessageVerifier.new('different-secret-key')
      
      expect {
        verifier2.verify(token1)
      }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
    end
  end
end 