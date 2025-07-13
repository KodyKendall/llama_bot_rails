# frozen_string_literal: true
module LlamaBotRails
    module ControllerExtensions
      extend ActiveSupport::Concern

      included do
        # NEW: per-controller class attribute that stores the allow-list
        class_attribute :llama_bot_permitted_actions,
                        instance_writer: false,
                        default: []
      end
  
      class_methods do
        # Usage: llama_bot_allow :update, :preview
        def llama_bot_allow(*actions)
            # normalise to strings so `include?(action_name)` works
            acts = actions.map(&:to_s)
          
            # Check if this specific class has had llama_bot_allow called directly on it
            if instance_variable_defined?(:@_llama_bot_allow_called)
              # This class has been configured before, accumulate with existing
              current_actions = llama_bot_permitted_actions || []
            else
              # First time configuring this class, start fresh (ignore inherited values)
              current_actions = []
              @_llama_bot_allow_called = true
            end
            
            # Create a new array to ensure inheritance doesn't share state
            self.llama_bot_permitted_actions = (current_actions + acts).uniq
          
            # (optional) keep your global registry if you still need it
            if defined?(LlamaBotRails.allowed_routes)
              acts.each { |a| LlamaBotRails.allowed_routes << "#{controller_path}##{a}" }
            end
          end
      end
    end
  end
  