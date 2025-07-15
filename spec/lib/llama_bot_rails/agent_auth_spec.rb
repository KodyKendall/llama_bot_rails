require 'rails_helper'

RSpec.describe LlamaBotRails::AgentAuth, type: :controller do
  let(:test_controller_class) do
    Class.new(ActionController::Base) do
      include LlamaBotRails::AgentAuth
      include LlamaBotRails::ControllerExtensions
      
      def action_name
        'test_action'
      end
      
      def self.controller_path
        'test'
      end
    end
  end
  
  let(:controller) { test_controller_class.new }
  let(:request) { double('request', headers: {}, env: {}) }
  let(:warden) { double('warden') }
  
  before do
    allow(controller).to receive(:request).and_return(request)
    allow(controller).to receive(:render)
    allow(controller).to receive(:head)
    allow(Rails).to receive(:logger).and_return(double('logger', debug: nil, warn: nil))
    
    # Mock request environment
    allow(request).to receive(:env).and_return('warden' => warden)
  end

  describe '#llama_bot_authenticated_request?' do
    let(:token) { Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test'}) }
    
    context 'with valid LlamaBot token' do
      before do
        allow(request).to receive(:headers).and_return({
          'Authorization' => "LlamaBot #{token}"
        })
      end
      
      it 'returns true' do
        expect(controller.llama_bot_authenticated_request?).to be true
      end
    end
    
    context 'with invalid token signature' do
      before do
        allow(request).to receive(:headers).and_return({
          'Authorization' => 'LlamaBot invalid-token'
        })
      end
      
      it 'returns false' do
        expect(controller.llama_bot_authenticated_request?).to be false
      end
    end
    
    context 'with missing Authorization header' do
      before do
        allow(request).to receive(:headers).and_return({})
      end
      
      it 'returns false' do
        expect(controller.llama_bot_authenticated_request?).to be false
      end
    end
    
    context 'with wrong auth scheme' do
      before do
        allow(request).to receive(:headers).and_return({
          'Authorization' => "Bearer #{token}"
        })
      end
      
      it 'returns false' do
        expect(controller.llama_bot_authenticated_request?).to be false
      end
    end
    
    context 'with expired token' do
      let(:expired_token) do
        Rails.application.message_verifier(:llamabot_ws).generate(
          {session_id: 'test'}, 
          expires_in: -1.minute
        )
      end
      
      before do
        allow(request).to receive(:headers).and_return({
          'Authorization' => "LlamaBot #{expired_token}"
        })
      end
      
      it 'returns false' do
        expect(controller.llama_bot_authenticated_request?).to be false
      end
    end
  end

  describe '#authenticate_user_or_agent!' do
    context 'when Devise user is signed in' do
      before do
        allow(controller).to receive(:devise_user_signed_in?).and_return(true)
      end
      
      it 'allows access without checking agent token' do
        expect(controller).not_to receive(:llama_bot_authenticated_request?)
        controller.send(:authenticate_user_or_agent!)
      end
    end
    
    context 'when no Devise user is signed in' do
      before do
        allow(controller).to receive(:devise_user_signed_in?).and_return(false)
      end
      
      context 'with valid agent token and whitelisted action' do
        let(:token) { Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test'}) }
        
        before do
          allow(request).to receive(:headers).and_return({
            'Authorization' => "LlamaBot #{token}"
          })
          
          # Mock the controller to have the action whitelisted
          allow(controller.class).to receive(:respond_to?).and_return(true)
          allow(controller.class).to receive(:llama_bot_permitted_actions).and_return(['test_action'])
        end
        
        it 'allows access' do
          expect(controller).not_to receive(:render)
          expect(controller).not_to receive(:head)
          controller.send(:authenticate_user_or_agent!)
        end
      end
      
      context 'with valid agent token but non-whitelisted action' do
        let(:token) { Rails.application.message_verifier(:llamabot_ws).generate({session_id: 'test'}) }
        
        before do
          allow(request).to receive(:headers).and_return({
            'Authorization' => "LlamaBot #{token}"
          })
          
          # Mock the controller to NOT have the action whitelisted
          allow(controller.class).to receive(:respond_to?).and_return(true)
          allow(controller.class).to receive(:llama_bot_permitted_actions).and_return([])
        end
        
        it 'renders forbidden response' do
          expect(controller).to receive(:render).with(
            json: { error: "Action 'test_action' isn't white-listed for LlamaBot. To fix this, include LlamaBotRails::ControllerExtensions and add `llama_bot_allow :method` in your controller." },
            status: :forbidden
          )
          
          result = controller.send(:authenticate_user_or_agent!)
          expect(result).to be false
        end
      end
      
      context 'with invalid agent token' do
        before do
          allow(request).to receive(:headers).and_return({
            'Authorization' => 'LlamaBot invalid-token'
          })
          allow(warden).to receive(:authenticate!)
        end
        
        context 'with Devise available' do
          before do
            stub_const('Devise', double('Devise'))
          end
          
          it 'delegates to Devise authentication' do
            expect(warden).to receive(:authenticate!)
            controller.send(:authenticate_user_or_agent!)
          end
        end
        
        context 'without Devise available' do
          before do
            hide_const('Devise')
          end
          
          it 'returns unauthorized' do
            expect(controller).to receive(:head).with(:unauthorized)
            controller.send(:authenticate_user_or_agent!)
          end
        end
      end
    end
  end

  describe 'Devise integration' do
    context 'when Devise is available' do
      before do
        devise_mappings = double('mappings', keys: [:user, :admin])
        stub_const('Devise', double('Devise', mappings: devise_mappings))
      end
      
      it 'aliases Devise authentication methods' do
        # Create a new controller class to test the included behavior
        klass = Class.new(ActionController::Base) do
          def authenticate_user!
            "original_method"
          end
          
          include LlamaBotRails::AgentAuth
        end
        
        controller_instance = klass.new
        allow(controller_instance).to receive(:authenticate_user_or_agent!).and_return("new_method")
        
        # The original method should now call authenticate_user_or_agent!
        expect(controller_instance.authenticate_user!).to eq("new_method")
      end
    end
    
    context 'when Devise is not available' do
      before do
        hide_const('Devise')
      end
      
      it 'creates fallback alias for authenticate_user!' do
        klass = Class.new(ActionController::Base) do
          def authenticate_user!
            "original_method"
          end
          
          include LlamaBotRails::AgentAuth
        end
        
        controller_instance = klass.new
        allow(controller_instance).to receive(:authenticate_user_or_agent!).and_return("new_method")
        
        expect(controller_instance.send(:authenticate_user!)).to eq("new_method")
      end
    end
  end

  describe '#devise_user_signed_in?' do
    context 'when Devise is available' do
      before do
        stub_const('Devise', double('Devise'))
      end
      
      it 'returns true when warden is authenticated' do
        allow(warden).to receive(:authenticated?).and_return(true)
        expect(controller.send(:devise_user_signed_in?)).to be true
      end
      
      it 'returns false when warden is not authenticated' do
        allow(warden).to receive(:authenticated?).and_return(false)
        expect(controller.send(:devise_user_signed_in?)).to be false
      end
      
      it 'returns false when warden is not available' do
        allow(request).to receive(:env).and_return({})
        expect(controller.send(:devise_user_signed_in?)).to be_falsy
      end
    end
    
    context 'when Devise is not available' do
      before do
        hide_const('Devise')
      end
      
      it 'returns false' do
        expect(controller.send(:devise_user_signed_in?)).to be false
      end
    end
  end
end 