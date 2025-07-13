require 'rails_helper'

RSpec.describe LlamaBotRails::ControllerExtensions do
  let(:test_controller_class) do
    Class.new(ActionController::Base) do
      include LlamaBotRails::ControllerExtensions
      
      def self.controller_path
        'test_controller'
      end
    end
  end
  
  before do
    # Reset the global allowed_routes before each test
    LlamaBotRails.allowed_routes.clear
  end
  
  describe 'when included in a controller' do
    it 'adds llama_bot_permitted_actions class attribute' do
      expect(test_controller_class).to respond_to(:llama_bot_permitted_actions)
      expect(test_controller_class.llama_bot_permitted_actions).to eq([])
    end
    
    it 'makes llama_bot_permitted_actions not writable from instances' do
      instance = test_controller_class.new
      expect(instance).not_to respond_to(:llama_bot_permitted_actions=)
    end
    
    it 'provides default empty array for llama_bot_permitted_actions' do
      expect(test_controller_class.llama_bot_permitted_actions).to eq([])
    end
  end
  
  describe '.llama_bot_allow' do
    context 'with single action' do
      before do
        test_controller_class.llama_bot_allow(:update)
      end
      
      it 'adds action to permitted_actions as string' do
        expect(test_controller_class.llama_bot_permitted_actions).to include('update')
      end
      
      it 'adds route to global allowed_routes' do
        expect(LlamaBotRails.allowed_routes).to include('test_controller#update')
      end
    end
    
    context 'with multiple actions' do
      before do
        test_controller_class.llama_bot_allow(:update, :show, :create)
      end
      
      it 'adds all actions to permitted_actions' do
        expect(test_controller_class.llama_bot_permitted_actions).to include('update', 'show', 'create')
      end
      
      it 'adds all routes to global allowed_routes' do
        expect(LlamaBotRails.allowed_routes).to include(
          'test_controller#update',
          'test_controller#show', 
          'test_controller#create'
        )
      end
    end
    
    context 'with string actions' do
      before do
        test_controller_class.llama_bot_allow('update', 'show')
      end
      
      it 'converts strings to strings and stores them' do
        expect(test_controller_class.llama_bot_permitted_actions).to include('update', 'show')
      end
    end
    
    context 'with duplicate actions' do
      before do
        test_controller_class.llama_bot_allow(:update, :show)
        test_controller_class.llama_bot_allow(:update, :create)
      end
      
      it 'removes duplicates from permitted_actions' do
        expect(test_controller_class.llama_bot_permitted_actions.count('update')).to eq(1)
        expect(test_controller_class.llama_bot_permitted_actions).to include('update', 'show', 'create')
      end
      
      it 'handles duplicates in global allowed_routes' do
        # Set should naturally handle duplicates
        update_routes = LlamaBotRails.allowed_routes.select { |route| route.include?('update') }
        expect(update_routes.count).to eq(1)
      end
    end
    
    context 'called multiple times' do
      it 'accumulates actions' do
        test_controller_class.llama_bot_allow(:update)
        expect(test_controller_class.llama_bot_permitted_actions).to eq(['update'])
        
        test_controller_class.llama_bot_allow(:show, :create)
        expect(test_controller_class.llama_bot_permitted_actions).to eq(['update', 'show', 'create'])
      end
    end
    
    context 'with no global allowed_routes defined' do
      before do
        # Temporarily remove the global allowed_routes
        allow(LlamaBotRails).to receive(:respond_to?).with(:allowed_routes).and_return(false)
      end
      
      it 'still works without global registry' do
        expect {
          test_controller_class.llama_bot_allow(:update)
        }.not_to raise_error
        
        expect(test_controller_class.llama_bot_permitted_actions).to include('update')
      end
    end
  end
  
  describe 'inheritance behavior' do
    let(:parent_controller_class) do
      Class.new(ActionController::Base) do
        include LlamaBotRails::ControllerExtensions
        
        def self.controller_path
          'parent_controller'
        end
      end
    end
    
    let(:child_controller_class) do
      Class.new(parent_controller_class) do
        def self.controller_path
          'child_controller'
        end
      end
    end
    
    before do
      parent_controller_class.llama_bot_allow(:index, :show)
      child_controller_class.llama_bot_allow(:update, :destroy)
    end
    
    it 'child class has its own permitted_actions' do
      expect(child_controller_class.llama_bot_permitted_actions).to include('update', 'destroy')
      expect(child_controller_class.llama_bot_permitted_actions).not_to include('index', 'show')
    end
    
    it 'parent class keeps its own permitted_actions' do
      expect(parent_controller_class.llama_bot_permitted_actions).to include('index', 'show')
      expect(parent_controller_class.llama_bot_permitted_actions).not_to include('update', 'destroy')
    end
    
    it 'adds correct routes to global registry' do
      expect(LlamaBotRails.allowed_routes).to include(
        'parent_controller#index',
        'parent_controller#show',
        'child_controller#update',
        'child_controller#destroy'
      )
    end
  end
  
  describe 'integration with multiple controllers' do
    let(:users_controller_class) do
      Class.new(ActionController::Base) do
        include LlamaBotRails::ControllerExtensions
        
        def self.controller_path
          'users'
        end
      end
    end
    
    let(:posts_controller_class) do
      Class.new(ActionController::Base) do
        include LlamaBotRails::ControllerExtensions
        
        def self.controller_path
          'posts'
        end
      end
    end
    
    before do
      users_controller_class.llama_bot_allow(:index, :show)
      posts_controller_class.llama_bot_allow(:create, :update)
    end
    
    it 'each controller has its own permitted_actions' do
      expect(users_controller_class.llama_bot_permitted_actions).to eq(['index', 'show'])
      expect(posts_controller_class.llama_bot_permitted_actions).to eq(['create', 'update'])
    end
    
    it 'global registry contains all allowed routes' do
      expect(LlamaBotRails.allowed_routes).to include(
        'users#index',
        'users#show',
        'posts#create',
        'posts#update'
      )
    end
  end
  
  describe 'edge cases' do
    context 'with empty action list' do
      it 'handles empty allow list gracefully' do
        expect {
          test_controller_class.llama_bot_allow
        }.not_to raise_error
        
        expect(test_controller_class.llama_bot_permitted_actions).to eq([])
      end
    end
    
    context 'with nil actions' do
      it 'handles nil actions gracefully' do
        expect {
          test_controller_class.llama_bot_allow(nil)
        }.not_to raise_error
        
        expect(test_controller_class.llama_bot_permitted_actions).to include('')
      end
    end
    
    context 'with mixed symbol and string actions' do
      before do
        test_controller_class.llama_bot_allow(:update, 'show', :create, 'destroy')
      end
      
      it 'normalizes all to strings' do
        expect(test_controller_class.llama_bot_permitted_actions).to all(be_a(String))
        expect(test_controller_class.llama_bot_permitted_actions).to include('update', 'show', 'create', 'destroy')
      end
    end
  end
end 