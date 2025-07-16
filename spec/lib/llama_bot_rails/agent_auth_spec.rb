require 'rails_helper'

RSpec.describe LlamaBotRails::AgentAuth do
  let(:controller_class) do
    Class.new(ActionController::Base) do
      include LlamaBotRails::AgentAuth
      include LlamaBotRails::ControllerExtensions
      
      llama_bot_allow :allowed_action
      
      def allowed_action
        render json: { message: 'success' }
      end
      
      def not_allowed_action
        render json: { message: 'should not reach here' }
      end
    end
  end
  
  let(:controller) { controller_class.new }
  let(:request) { double('request') }
  let(:headers) { {} }
  let(:env) { {} }
  
  before do
    allow(controller).to receive(:request).and_return(request)
    allow(request).to receive(:headers).and_return(headers)
    allow(request).to receive(:env).and_return(env)
    allow(controller).to receive(:action_name).and_return('allowed_action')
    allow(controller).to receive(:render)
    allow(controller).to receive(:head)
    
    # Clear any existing user resolvers
    LlamaBotRails.user_resolver = nil
    LlamaBotRails.current_user_resolver = nil
    LlamaBotRails.sign_in_method = nil
  end

  describe '#llama_bot_request?' do
    context 'with no authorization header' do
      it 'returns false' do
        expect(controller.send(:llama_bot_request?)).to be false
      end
    end

    context 'with incorrect scheme' do
      before do
        headers['Authorization'] = 'Bearer some-token'
      end

      it 'returns false' do
        expect(controller.send(:llama_bot_request?)).to be false
      end
    end

    context 'with correct scheme but invalid token' do
      before do
        headers['Authorization'] = 'LlamaBot invalid-token'
      end

      it 'returns false due to verification failure' do
        allow(Rails.application.message_verifier(:llamabot_ws))
          .to receive(:verify)
          .and_raise(ActiveSupport::MessageVerifier::InvalidSignature)
        
        expect(controller.send(:llama_bot_request?)).to be false
      end
    end

    context 'with valid LlamaBot token' do
      let(:valid_token) { 'valid-token' }
      
      before do
        headers['Authorization'] = "LlamaBot #{valid_token}"
        allow(Rails.application.message_verifier(:llamabot_ws))
          .to receive(:verify)
          .with(valid_token)
          .and_return({ session_id: 'test', user_id: 123 })
      end

      it 'returns true' do
        expect(controller.send(:llama_bot_request?)).to be true
      end
    end
  end

  describe '#check_agent_authentication' do
    let(:valid_token) { 'valid-token' }
    let(:token_data) { { session_id: 'test-session', user_id: 123 } }

    before do
      headers['Authorization'] = "LlamaBot #{valid_token}"
      allow(Rails.application.message_verifier(:llamabot_ws))
        .to receive(:verify)
        .with(valid_token)
        .and_return(token_data)
    end

    context 'when action is not whitelisted and no valid LlamaBot request' do
      before do
        # Make action_name return something not in the allowed list
        allow(controller).to receive(:action_name).and_return('not_allowed_action')
        headers.clear
      end

      it 'allows the request to proceed normally' do
        expect(controller).not_to receive(:render)
        controller.send(:check_agent_authentication)
      end
    end

    context 'when action requires LlamaBot auth but is not a valid LlamaBot request' do
      before do
        # Make action_name return something in the allowed list
        allow(controller).to receive(:action_name).and_return('allowed_action')
        headers.clear
      end

      it 'renders forbidden error' do
        expect(controller).to receive(:render).with(
          json: { error: "Action 'allowed_action' requires LlamaBot authentication" },
          status: :forbidden
        )
        
        controller.send(:check_agent_authentication)
      end
    end

    context 'when action is whitelisted' do
      it 'proceeds without error' do
        expect(controller).not_to receive(:render)
        controller.send(:check_agent_authentication)
      end
    end

    context 'when LlamaBot request is made to non-whitelisted action' do
      before do
        # Make llama_bot_request? return true but action not whitelisted
        allow(controller).to receive(:llama_bot_request?).and_return(true)
        allow(controller).to receive(:action_name).and_return('not_allowed_action')
      end

      it 'renders forbidden error' do
        expect(controller).to receive(:render).with(
          json: { error: "Action 'not_allowed_action' isn't white-listed for LlamaBot. To fix this, add `llama_bot_allow :not_allowed_action` in your controller." },
          status: :forbidden
        )
        controller.send(:check_agent_authentication)
      end
    end

    context 'when token verification passes' do
      before do
        # Make llama_bot_request? return true and action whitelisted
        allow(controller).to receive(:llama_bot_request?).and_return(true)
        allow(controller).to receive(:action_name).and_return('allowed_action')
      end

      it 'logs success and continues processing' do
        expect(Rails.logger).to receive(:debug).with(match(/Valid LlamaBot request for action/))
        controller.send(:check_agent_authentication)
      end
    end
  end

  describe '#authenticate_user_or_agent!' do
    let(:valid_token) { 'valid-token' }
    let(:user_id) { 123 }
    let(:token_data) { { session_id: 'test-session', user_id: user_id } }
    let(:mock_user) { double('User', id: user_id) }

    before do
      headers['Authorization'] = "LlamaBot #{valid_token}"
      allow(Rails.application.message_verifier(:llamabot_ws))
        .to receive(:verify)
        .with(valid_token)
        .and_return(token_data)
    end

    context 'when user is already signed in via Devise' do
      before do
        allow(controller).to receive(:devise_user_signed_in?).and_return(true)
      end

      it 'returns early without checking agent auth' do
        expect(controller).not_to receive(:llama_bot_request?)
        controller.send(:authenticate_user_or_agent!)
      end
    end

    context 'when user is not signed in but valid agent request' do
      before do
        allow(controller).to receive(:devise_user_signed_in?).and_return(false)
        
        # Set up user resolver
        LlamaBotRails.user_resolver = ->(id) { mock_user if id == user_id }
        LlamaBotRails.sign_in_method = ->(env, user) { true }
      end

      it 'resolves user and signs them in' do
        expect(LlamaBotRails.user_resolver).to receive(:call).with(user_id).and_return(mock_user)
        expect(LlamaBotRails.sign_in_method).to receive(:call).with(env, mock_user).and_return(true)
        
        controller.send(:authenticate_user_or_agent!)
      end

      context 'when user cannot be found' do
        before do
          LlamaBotRails.user_resolver = ->(id) { nil }
        end

        it 'calls sign in method with nil user' do
          expect(LlamaBotRails.sign_in_method).to receive(:call).with(env, nil).and_return(true)
          controller.send(:authenticate_user_or_agent!)
        end
      end

      context 'when sign in fails' do
        before do
          LlamaBotRails.sign_in_method = ->(env, user) { false }
        end

        it 'returns unauthorized' do
          expect(controller).to receive(:head).with(:unauthorized)
          controller.send(:authenticate_user_or_agent!)
        end
      end

      context 'when action is not whitelisted' do
        before do
          allow(controller).to receive(:action_name).and_return('not_allowed_action')
        end

        it 'renders forbidden error' do
          expect(controller).to receive(:render).with(
            json: { error: match(/isn't white-listed/) },
            status: :forbidden
          )
          
          controller.send(:authenticate_user_or_agent!)
        end
      end
    end

    context 'when neither Devise nor agent auth succeeds' do
      before do
        allow(controller).to receive(:devise_user_signed_in?).and_return(false)
        
        # Make llama_bot_request? return false (no valid agent token)
        allow(controller).to receive(:llama_bot_request?).and_return(false)
        
        # Mock Devise environment
        warden = double('warden')
        env['warden'] = warden
        
        # Mock Devise constant being defined
        unless defined?(Devise)
          stub_const('Devise', double('Devise'))
        end
      end

      it 'falls back to Devise authentication' do
        expect(env['warden']).to receive(:authenticate!)
        controller.send(:authenticate_user_or_agent!)
      end

      context 'when Devise is not available' do
        before do
          env.clear # Remove warden
          # Also undefine Devise for this test
          hide_const('Devise') if defined?(Devise)
        end

        it 'returns unauthorized' do
          expect(controller).to receive(:head).with(:unauthorized)
          controller.send(:authenticate_user_or_agent!)
        end
      end
    end
  end

  describe '#devise_user_signed_in?' do
    context 'when Devise is not defined' do
      before do
        hide_const('Devise')
      end

      it 'returns false' do
        expect(controller.send(:devise_user_signed_in?)).to be false
      end
    end

    context 'when request env is not available' do
      before do
        allow(controller).to receive(:request).and_return(nil)
      end

      it 'returns false' do
        expect(controller.send(:devise_user_signed_in?)).to be false
      end
    end

    context 'when Devise is available and user is authenticated' do
      before do
        stub_const('Devise', double)
        warden = double('warden')
        env['warden'] = warden
        allow(warden).to receive(:authenticated?).and_return(true)
      end

      it 'returns true' do
        expect(controller.send(:devise_user_signed_in?)).to be true
      end
    end

    context 'when Devise is available but user is not authenticated' do
      before do
        stub_const('Devise', double)
        warden = double('warden')
        env['warden'] = warden
        allow(warden).to receive(:authenticated?).and_return(false)
      end

      it 'returns false' do
        expect(controller.send(:devise_user_signed_in?)).to be false
      end
    end
  end
end 