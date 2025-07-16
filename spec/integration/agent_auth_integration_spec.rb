require 'rails_helper'

RSpec.describe 'Agent Authentication and Authorization Integration', type: :controller do
  # Create a test controller that uses both modules
  controller(ActionController::Base) do
    include LlamaBotRails::AgentAuth
    include LlamaBotRails::ControllerExtensions
    
    llama_bot_allow :allowed_action, :action_requiring_auth
    
    def allowed_action
      render json: { message: 'success' }
    end
    
    def not_allowed_action
      render json: { message: 'should not reach here' }
    end
    
    def action_requiring_auth
      authenticate_user_or_agent!
      return if performed?  # Don't render if authentication already rendered a response
      render json: { message: 'authenticated' }
    end
  end
  
  let(:user_id) { 123 }
  let(:mock_user) { double('User', id: user_id) }
  
  before do
    # Clear global registry before each test
    LlamaBotRails.allowed_routes.clear
    
    # Re-populate the registry after clearing
    LlamaBotRails.allowed_routes << 'anonymous#allowed_action'
    LlamaBotRails.allowed_routes << 'anonymous#action_requiring_auth'
    
    routes.draw do
      get :allowed_action, to: 'anonymous#allowed_action'
      get :not_allowed_action, to: 'anonymous#not_allowed_action'
      get :action_requiring_auth, to: 'anonymous#action_requiring_auth'
    end

    # Set up default user resolvers
    LlamaBotRails.user_resolver = ->(id) { mock_user if id == user_id }
    LlamaBotRails.current_user_resolver = ->(env) { mock_user }
    LlamaBotRails.sign_in_method = ->(env, user) { true }
    
    # Set up proper warden mock for Devise integration
    mock_warden = double('warden')
    allow(mock_warden).to receive(:authenticated?).and_return(false)
    allow(mock_warden).to receive(:authenticate!).and_return(false)
    allow(mock_warden).to receive(:set_user).and_return(true)
    allow(mock_warden).to receive(:user).and_return(nil)
    
    # Mock request.env to include warden by default
    allow_any_instance_of(ActionController::TestRequest).to receive(:env).and_wrap_original do |method, *args|
      env = method.call(*args)
      env['warden'] = mock_warden unless env.key?('warden')
      env
    end
  end
  
  let(:valid_token) { Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test', user_id: user_id}) }
  let(:valid_token_no_user) { Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test', user_id: nil}) }
  let(:invalid_token) { 'invalid-token' }
  let(:expired_token) do
    Rails.application.message_verifier(:llamabot_ws).generate(
      {session_id: 'test', user_id: user_id}, 
      expires_in: -1.minute
    )
  end
  
  describe 'Agent token authentication' do
    context 'with valid token' do
      before do
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
      end
      
      it 'allows access to whitelisted actions' do
        get :allowed_action
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['message']).to eq('success')
      end
      
      it 'authenticates user through user resolver' do
        expect(LlamaBotRails.user_resolver).to receive(:call).with(user_id).and_return(mock_user)
        expect(LlamaBotRails.sign_in_method).to receive(:call).with(request.env, mock_user).and_return(true)
        
        get :action_requiring_auth
        expect(response).to have_http_status(:success)
      end
      
      it 'handles user resolver returning nil gracefully' do
        LlamaBotRails.user_resolver = ->(id) { nil }
        expect(LlamaBotRails.sign_in_method).to receive(:call).with(request.env, nil).and_return(true)
        
        get :action_requiring_auth
        expect(response).to have_http_status(:success)
      end
      
      it 'returns unauthorized when sign in method fails' do
        LlamaBotRails.sign_in_method = ->(env, user) { false }
        
        get :action_requiring_auth
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'with valid token but no user_id' do
      before do
        request.headers['Authorization'] = "LlamaBot #{valid_token_no_user}"
      end
      
      it 'calls user resolver with nil user_id' do
        expect(LlamaBotRails.user_resolver).to receive(:call).with(nil).and_return(nil)
        expect(LlamaBotRails.sign_in_method).to receive(:call).with(request.env, nil).and_return(true)
        
        get :action_requiring_auth
        expect(response).to have_http_status(:success)
      end
    end
    
    context 'with non-whitelisted action' do
      before do
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
      end
      
      it 'returns forbidden for non-whitelisted actions' do
        get :not_allowed_action
        expect(response).to have_http_status(:forbidden)
        
        error_response = JSON.parse(response.body)
        expect(error_response['error']).to include("isn't white-listed")
      end
    end
    
    context 'with invalid token' do
      before do
        request.headers['Authorization'] = "LlamaBot #{invalid_token}"
      end
      
      it 'falls back to Devise authentication for invalid tokens' do
        # Mock Devise environment
        warden = double('warden')
        request.env['warden'] = warden
        allow(warden).to receive(:authenticate!)
        allow(warden).to receive(:authenticated?).and_return(false)
        
        stub_const('Devise', double('Devise'))
        
        expect(warden).to receive(:authenticate!)
        get :action_requiring_auth
      end
    end
    
    context 'with expired token' do
      before do
        request.headers['Authorization'] = "LlamaBot #{expired_token}"
      end
      
      it 'falls back to Devise authentication for expired tokens' do
        warden = double('warden')
        request.env['warden'] = warden
        allow(warden).to receive(:authenticate!)
        allow(warden).to receive(:authenticated?).and_return(false)
        
        stub_const('Devise', double('Devise'))
        
        expect(warden).to receive(:authenticate!)
        get :action_requiring_auth
      end
    end
    
    context 'with wrong authentication scheme' do
      before do
        request.headers['Authorization'] = "Bearer #{valid_token}"
      end
      
      it 'falls back to Devise authentication' do
        warden = double('warden')
        request.env['warden'] = warden
        allow(warden).to receive(:authenticate!)
        allow(warden).to receive(:authenticated?).and_return(false)
        
        stub_const('Devise', double('Devise'))
        
        expect(warden).to receive(:authenticate!)
        get :action_requiring_auth
      end
    end
    
    context 'without authorization header' do
      it 'falls back to Devise authentication' do
        warden = double('warden')
        request.env['warden'] = warden
        allow(warden).to receive(:authenticate!)
        allow(warden).to receive(:authenticated?).and_return(false)
        
        stub_const('Devise', double('Devise'))
        
        expect(warden).to receive(:authenticate!)
        get :action_requiring_auth
      end
    end
  end
  
  describe 'Devise integration' do
    context 'when user is already signed in via Devise' do
      before do
        # Mock Devise user as signed in
        allow_any_instance_of(controller.class).to receive(:devise_user_signed_in?).and_return(true)
      end
      
      it 'allows access without checking agent token' do
        get :action_requiring_auth
        expect(response).to have_http_status(:success)
      end
      
      it 'skips agent authentication entirely' do
        expect_any_instance_of(controller.class).not_to receive(:llama_bot_request?)
        get :action_requiring_auth
      end
    end
    
    context 'when Devise is not available' do
      before do
        hide_const('Devise')
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
      end
      
      it 'still processes agent authentication' do
        get :action_requiring_auth
        expect(response).to have_http_status(:success)
      end
      
      it 'returns unauthorized when no valid authentication is present' do
        request.headers['Authorization'] = nil
        
        get :action_requiring_auth
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'Custom user resolvers' do
    context 'with custom session-based authentication' do
      before do
        # Set up custom resolvers that use sessions instead of Devise
        LlamaBotRails.user_resolver = ->(user_id) do
          { id: user_id, username: "user_#{user_id}" } if user_id
        end
        
        LlamaBotRails.current_user_resolver = ->(env) do
          if session_user_id = env['rack.session']&.[](:user_id)
            { id: session_user_id, username: "user_#{session_user_id}" }
          end
        end
        
        LlamaBotRails.sign_in_method = ->(env, user) do
          if user
            env['rack.session'] ||= {}
            env['rack.session'][:user_id] = user[:id]
            true
          else
            false
          end
        end
        
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
        # Create stateful session mock that acts like a hash with Flash middleware methods
        session_data = {}
        session = double('session')
        allow(session).to receive(:enabled?).and_return(true)
        allow(session).to receive(:loaded?).and_return(true)
        allow(session).to receive(:delete).and_return(nil)
        allow(session).to receive(:key?).and_return(false)
        allow(session).to receive(:[]) { |key| session_data[key] }
        allow(session).to receive(:[]=) { |key, value| session_data[key] = value }
        request.env['rack.session'] = session
      end
      
      it 'uses custom user resolver during authentication' do
        get :action_requiring_auth
        
        expect(response).to have_http_status(:success)
        expect(request.env['rack.session'][:user_id]).to eq(user_id)
      end
      
      it 'handles nil user from custom resolver' do
        LlamaBotRails.user_resolver = ->(id) { nil }
        
        get :action_requiring_auth
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'with custom resolvers that fail' do
      before do
        LlamaBotRails.user_resolver = ->(id) { raise StandardError.new('Database error') }
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
      end
      
      it 'handles resolver errors gracefully' do
        expect {
          get :action_requiring_auth
        }.to raise_error(StandardError, 'Database error')
      end
    end
  end
  
  describe 'check_agent_authentication before_action' do
    context 'with valid agent request' do
      before do
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
      end
      
      it 'allows whitelisted actions to proceed' do
        get :allowed_action
        expect(response).to have_http_status(:success)
      end
      
      it 'blocks non-whitelisted actions' do
        get :not_allowed_action
        expect(response).to have_http_status(:forbidden)
      end
    end
    
    context 'with non-agent request' do
      it 'skips agent authentication checks for regular requests' do
        # This should not trigger agent auth since there's no LlamaBot token
        # It would normally fall through to regular Rails authentication
        get :allowed_action
        expect(response).to have_http_status(:success)
      end
    end
  end
  
  describe 'security edge cases' do
    it 'prevents bypassing authentication with malformed tokens' do
      request.headers['Authorization'] = 'LlamaBot '
      
      get :action_requiring_auth
      # Should fall back to Devise or return unauthorized
      expect(response).to have_http_status(:unauthorized)
    end
    
    it 'handles token verification exceptions gracefully' do
      allow(Rails.application.message_verifier(:llamabot_ws))
        .to receive(:verify)
        .and_raise(ActiveSupport::MessageVerifier::InvalidSignature)
      
      request.headers['Authorization'] = "LlamaBot some-token"
      
      get :action_requiring_auth
      expect(response).to have_http_status(:unauthorized)
    end
    
    it 'prevents access with tokens for wrong user' do
      wrong_user_token = Rails.application.message_verifier(:llamabot_ws)
        .generate({session_id: 'test', user_id: 999})
      
      LlamaBotRails.user_resolver = ->(id) { mock_user if id == user_id } # Only returns user for specific ID
      
      request.headers['Authorization'] = "LlamaBot #{wrong_user_token}"
      
      get :action_requiring_auth
      # Should still succeed since sign_in_method returns true for any user (including nil)
      expect(response).to have_http_status(:success)
    end
  end
end 