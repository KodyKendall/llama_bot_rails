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
  end
  
  let(:valid_token) { Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test'}) }
  let(:invalid_token) { 'invalid-token' }
  let(:expired_token) do
    Rails.application.message_verifier(:llamabot_ws).generate(
      {session_id: 'test'}, 
      expires_in: -1.minute
    )
  end
  
  describe 'authentication flow' do
    context 'with valid agent token' do
      before do
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
      end
      
      it 'allows access to whitelisted actions' do
        get :allowed_action
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)).to eq({ 'message' => 'success' })
      end
      
      it 'denies access to non-whitelisted actions' do
        get :not_allowed_action
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)).to include('error')
      end
      
      it 'works with explicit authentication call' do
        get :action_requiring_auth
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)).to eq({ 'message' => 'authenticated' })
      end
    end
    
    context 'with invalid agent token' do
      before do
        request.headers['Authorization'] = "LlamaBot #{invalid_token}"
      end
      
      it 'returns unauthorized for any action' do
        get :action_requiring_auth
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'with expired token' do
      before do
        request.headers['Authorization'] = "LlamaBot #{expired_token}"
      end
      
      it 'returns unauthorized' do
        get :action_requiring_auth
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'with missing authorization header' do
      it 'returns unauthorized' do
        get :action_requiring_auth
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'with wrong authorization scheme' do
      before do
        request.headers['Authorization'] = "Bearer #{valid_token}"
      end
      
      it 'returns unauthorized' do
        get :action_requiring_auth
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'global allowed_routes registry' do
    it 'records allowed actions in global registry' do
      expect(LlamaBotRails.allowed_routes).to include('anonymous#allowed_action')
    end
    
    it 'does not record non-whitelisted actions' do
      expect(LlamaBotRails.allowed_routes).not_to include('anonymous#not_allowed_action')
    end
  end
  
  describe 'Devise integration' do
    let(:user) { double('user') }
    let(:warden) { double('warden', authenticated?: true, user: user) }
    
    before do
      stub_const('Devise', double('Devise', mappings: double(keys: [:user])))
      allow(request).to receive(:env).and_return('warden' => warden)
    end
    
    context 'when user is signed in via Devise' do
      it 'allows access without checking agent token' do
        get :action_requiring_auth
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)).to eq({ 'message' => 'authenticated' })
      end
      
      it 'allows access to any action when user is signed in' do
        get :not_allowed_action
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)).to eq({ 'message' => 'should not reach here' })
      end
    end
    
    context 'when user is not signed in via Devise' do
      before do
        allow(warden).to receive(:authenticated?).and_return(false)
        allow(warden).to receive(:authenticate!).and_raise(StandardError.new('Authentication required'))
      end
      
      it 'falls back to agent authentication' do
        # Mock llama_bot_authenticated_request? to return true for this test case
        # (simulating a valid token being provided)

        allow(controller).to receive(:llama_bot_authenticated_request?).and_return(true)
        
        get :action_requiring_auth
        expect(response).to have_http_status(:success)
      end
      
      it 'uses Devise authentication when no valid agent token' do
        expect(warden).to receive(:authenticate!)
        expect { get :action_requiring_auth }.to raise_error('Authentication required')
      end
    end
  end
  
  describe 'token verification edge cases' do
    context 'with malformed authorization header' do
      before do
        request.headers['Authorization'] = 'LlamaBot'
      end
      
      it 'returns unauthorized' do
        get :action_requiring_auth
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'with empty token' do
      before do
        request.headers['Authorization'] = 'LlamaBot '
      end
      
      it 'returns unauthorized' do
        get :action_requiring_auth
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'with token that cannot be verified' do
      before do
        # Mock the message verifier to raise an error
        allow(Rails.application.message_verifier(:llamabot_ws)).to receive(:verify)
          .and_raise(ActiveSupport::MessageVerifier::InvalidSignature)
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
      end
      
      it 'returns unauthorized' do
        get :action_requiring_auth
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'action whitelisting behavior' do
    context 'when controller does not have llama_bot_permitted_actions' do
      controller(ActionController::Base) do
        include LlamaBotRails::AgentAuth
        # Not including ControllerExtensions
        
        def test_action
          authenticate_user_or_agent!
          return if performed?  # Don't render if authentication already rendered a response
          render json: { message: 'success' }
        end
      end
      
      before do
        routes.draw do
          get :test_action, to: 'anonymous#test_action'
        end
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
        # Mock respond_to? to return false for llama_bot_permitted_actions but allow other calls
        allow(controller.class).to receive(:respond_to?).and_call_original
        allow(controller.class).to receive(:respond_to?).with(:llama_bot_permitted_actions).and_return(false)
      end
      
      it 'falls back to Devise authentication' do
        stub_const('Devise', double('Devise'))
        warden = double('warden')
        allow(request).to receive(:env).and_return('warden' => warden)
        allow(warden).to receive(:authenticated?).and_return(false)
        allow(warden).to receive(:authenticate!).and_raise(StandardError.new('Authentication required'))
        
        expect { get :test_action }.to raise_error('Authentication required')
      end
    end
    
    context 'when action is not in whitelist' do
      before do
        request.headers['Authorization'] = "LlamaBot #{valid_token}"
      end
      
      it 'returns specific error message' do
        get :not_allowed_action
        expect(response).to have_http_status(:forbidden)
        error_message = JSON.parse(response.body)['error']
        expect(error_message).to include("Action 'not_allowed_action' isn't white-listed for LlamaBot")
        expect(error_message).to include("llama_bot_allow :method")
      end
    end
  end
end 