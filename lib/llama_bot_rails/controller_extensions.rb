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
          
            # store on the per-controller attribute the guard uses
            self.llama_bot_permitted_actions += acts
            self.llama_bot_permitted_actions.uniq!
          
            # (optional) keep your global registry if you still need it
            if defined?(LlamaBotRails.allowed_routes)
              acts.each { |a| LlamaBotRails.allowed_routes << "#{controller_path}##{a}" }
            end
          end
      end
    end
  end
  