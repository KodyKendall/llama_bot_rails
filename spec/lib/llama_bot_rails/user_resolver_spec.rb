require 'rails_helper'

RSpec.describe 'LlamaBotRails User Resolvers' do
  before do
    # Store original resolvers to restore them after tests
    @original_user_resolver = LlamaBotRails.user_resolver
    @original_current_user_resolver = LlamaBotRails.current_user_resolver
    @original_sign_in_method = LlamaBotRails.sign_in_method
  end

  after do
    # Restore original resolvers
    LlamaBotRails.user_resolver = @original_user_resolver
    LlamaBotRails.current_user_resolver = @original_current_user_resolver
    LlamaBotRails.sign_in_method = @original_sign_in_method
  end

  describe '.user_resolver' do
    context 'with default Devise-based resolver' do
      let(:user_id) { 123 }
      let(:mock_user) { double('User', id: user_id) }
      let(:mock_user_class) { double('User class') }
      let(:mock_mapping) { double('mapping', to: mock_user_class) }
      let(:mock_devise) { double('Devise', default_scope: :user, mappings: { user: mock_mapping }) }

      before do
        stub_const('Devise', mock_devise)
      end

      it 'finds user by id when Devise is available' do
        expect(mock_user_class).to receive(:find_by).with(id: user_id).and_return(mock_user)
        
        result = LlamaBotRails.user_resolver.call(user_id)
        expect(result).to eq(mock_user)
      end

      it 'returns nil when user is not found' do
        expect(mock_user_class).to receive(:find_by).with(id: user_id).and_return(nil)
        
        result = LlamaBotRails.user_resolver.call(user_id)
        expect(result).to be_nil
      end

      it 'handles nil user_id gracefully' do
        expect(mock_user_class).to receive(:find_by).with(id: nil).and_return(nil)
        
        result = LlamaBotRails.user_resolver.call(nil)
        expect(result).to be_nil
      end
    end

    context 'without Devise available' do
      before do
        hide_const('Devise')
      end

      it 'logs warning and returns nil' do
        expect(Rails.logger).to receive(:warn).with(match(/Implement a user_resolver!/))
        
        result = LlamaBotRails.user_resolver.call(123)
        expect(result).to be_nil
      end
    end

    context 'with custom resolver' do
      let(:custom_user) { double('CustomUser', id: 456) }

      before do
        LlamaBotRails.user_resolver = ->(user_id) do
          custom_user if user_id == 456
        end
      end

      it 'uses the custom resolver' do
        result = LlamaBotRails.user_resolver.call(456)
        expect(result).to eq(custom_user)
      end

      it 'returns nil for non-matching user id' do
        result = LlamaBotRails.user_resolver.call(999)
        expect(result).to be_nil
      end
    end
  end

  describe '.current_user_resolver' do
    let(:env) { {} }

    context 'with default Devise-based resolver' do
      let(:mock_user) { double('User', id: 123) }
      let(:warden) { double('warden', user: mock_user) }

      before do
        stub_const('Devise', double('Devise'))
        env['warden'] = warden
      end

      it 'returns current user from warden' do
        result = LlamaBotRails.current_user_resolver.call(env)
        expect(result).to eq(mock_user)
      end

      it 'returns nil when warden has no user' do
        allow(warden).to receive(:user).and_return(nil)
        
        result = LlamaBotRails.current_user_resolver.call(env)
        expect(result).to be_nil
      end

      it 'returns nil when warden is not available' do
        env.clear
        
        result = LlamaBotRails.current_user_resolver.call(env)
        expect(result).to be_nil
      end
    end

    context 'without Devise available' do
      before do
        hide_const('Devise')
      end

      it 'logs warning and returns nil' do
        expect(Rails.logger).to receive(:warn).with(match(/Implement a current_user_resolver!/))
        
        result = LlamaBotRails.current_user_resolver.call(env)
        expect(result).to be_nil
      end
    end

    context 'with custom resolver' do
      let(:custom_user) { double('CustomUser', id: 789) }

      before do
        LlamaBotRails.current_user_resolver = ->(env) do
          if session_id = env['rack.session']&.[](:user_id)
            custom_user if session_id == 789
          end
        end

        env['rack.session'] = { user_id: 789 }
      end

      it 'uses the custom resolver' do
        result = LlamaBotRails.current_user_resolver.call(env)
        expect(result).to eq(custom_user)
      end

      it 'returns nil when session user id does not match' do
        env['rack.session'] = { user_id: 999 }
        
        result = LlamaBotRails.current_user_resolver.call(env)
        expect(result).to be_nil
      end

      it 'returns nil when no session available' do
        env.clear
        
        result = LlamaBotRails.current_user_resolver.call(env)
        expect(result).to be_nil
      end
    end
  end

  describe '.sign_in_method' do
    let(:env) { {} }
    let(:user) { double('User', id: 123) }

    context 'with default Devise-based sign in' do
      let(:warden) { double('warden') }

      before do
        env['warden'] = warden
      end

      it 'sets user in warden' do
        expect(warden).to receive(:set_user).with(user).and_return(true)
        
        result = LlamaBotRails.sign_in_method.call(env, user)
        expect(result).to be_truthy
      end

      it 'handles nil user gracefully' do
        expect(warden).to receive(:set_user).with(nil).and_return(true)
        
        result = LlamaBotRails.sign_in_method.call(env, nil)
        expect(result).to be_truthy
      end

      it 'returns nil when warden is not available' do
        env.clear
        
        result = LlamaBotRails.sign_in_method.call(env, user)
        expect(result).to be_nil
      end
    end

    context 'with custom sign in method' do
      before do
        LlamaBotRails.sign_in_method = ->(env, user) do
          if user
            env['rack.session'] ||= {}
            env['rack.session'][:user_id] = user.id
            true
          else
            false
          end
        end

        env['rack.session'] = {}
      end

      it 'sets user in custom session store' do
        result = LlamaBotRails.sign_in_method.call(env, user)
        
        expect(result).to be true
        expect(env['rack.session'][:user_id]).to eq(123)
      end

      it 'returns false for nil user' do
        result = LlamaBotRails.sign_in_method.call(env, nil)
        expect(result).to be false
      end
    end
  end

  describe 'integration with agent authentication' do
    let(:controller_class) do
      Class.new(ActionController::Base) do
        include LlamaBotRails::AgentAuth
        include LlamaBotRails::ControllerExtensions
        
        llama_bot_allow :test_action
        
        def test_action
          render json: { message: 'success' }
        end
      end
    end
    
    let(:controller) { controller_class.new }
    let(:request) { double('request') }
    let(:headers) { {} }
    let(:env) { {} }
    let(:user_id) { 456 }
    let(:mock_user) { double('User', id: user_id) }
    let(:valid_token) { 'valid-token' }
    let(:token_data) { { session_id: 'test-session', user_id: user_id } }

    before do
      allow(controller).to receive(:request).and_return(request)
      allow(request).to receive(:headers).and_return(headers)
      allow(request).to receive(:env).and_return(env)
      allow(controller).to receive(:action_name).and_return('test_action')
      allow(controller).to receive(:render)
      allow(controller).to receive(:head)
      allow(controller).to receive(:devise_user_signed_in?).and_return(false)

      headers['Authorization'] = "LlamaBot #{valid_token}"
      allow(Rails.application.message_verifier(:llamabot_ws))
        .to receive(:verify)
        .with(valid_token)
        .and_return(token_data)
    end

    it 'resolves user through custom resolver during authentication' do
      # Set up custom resolvers
      LlamaBotRails.user_resolver = ->(id) { mock_user if id == user_id }
      LlamaBotRails.sign_in_method = ->(env, user) { 
        env[:signed_in_user] = user
        true 
      }

      controller.send(:authenticate_user_or_agent!)

      expect(env[:signed_in_user]).to eq(mock_user)
    end

    it 'handles authentication failure when user resolver returns nil' do
      LlamaBotRails.user_resolver = ->(id) { nil }
      LlamaBotRails.sign_in_method = ->(env, user) { false }

      expect(controller).to receive(:head).with(:unauthorized)
      controller.send(:authenticate_user_or_agent!)
    end

    it 'handles authentication failure when sign in method fails' do
      LlamaBotRails.user_resolver = ->(id) { mock_user }
      LlamaBotRails.sign_in_method = ->(env, user) { false }

      expect(controller).to receive(:head).with(:unauthorized)
      controller.send(:authenticate_user_or_agent!)
    end
  end
end 