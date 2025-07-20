# lib/llama_bot_rails/agent_auth.rb
module LlamaBotRails
    module AgentAuth
      extend ActiveSupport::Concern
      AUTH_SCHEME = "LlamaBot"
  
      included do
        # ------------------------------------------------------------------
        # Use the right callback macro for the including class:
        #   • Controllers → before_action (old behaviour)
        #   • ActiveJob   → before_perform  (uses same checker)
        #   • Anything
        #     else       → do nothing
        # ------------------------------------------------------------------
        if respond_to?(:before_action)
          before_action :check_agent_authentication, if: :should_check_agent_auth?
        elsif respond_to?(:before_perform)
          before_perform :check_agent_authentication
        end
  
        # ------------------------------------------------------------------
        # 1) For every Devise scope, alias authenticate_<scope>! so it now
        #    accepts *either* a logged-in browser session OR a valid agent
        #    token. Existing before/skip filters keep working.
        # ------------------------------------------------------------------
        if defined?(Devise)
          Devise.mappings.keys.each do |scope|
            scope_filter = :"authenticate_#{scope}!"
  
            alias_method scope_filter, :authenticate_user_or_agent! \
              if method_defined?(scope_filter)
  
            define_method(scope_filter) do |*args|
              Rails.logger.warn(
                "#{scope_filter} is now handled by LlamaBotRails::AgentAuth "\
                "and will be removed in a future version. "\
                "Use authenticate_user_or_agent! instead."
              )
              authenticate_user_or_agent!(*args)
            end
          end
        end
  
        # ------------------------------------------------------------------
        # 2) If Devise isn’t loaded at all, fall back to one alias so apps
        #    that had authenticate_user! manually defined don’t break.
        # ------------------------------------------------------------------
        unless defined?(Devise)
          original_authenticate_user =
            instance_method(:authenticate_user!) if method_defined?(:authenticate_user!)
  
          define_method(:authenticate_user!) do |*args|
            authenticate_user_or_agent!(*args)
          end
        end
      end
  
      # --------------------------------------------------------------------
      # Public helper: true if the request carries a *valid* agent token
      # --------------------------------------------------------------------
      def should_check_agent_auth?
        # Skip if a Devise user is already signed in
        return false if devise_user_signed_in?
        llama_bot_request?
      end
  
      def llama_bot_request?
        return false unless respond_to?(:request) && request&.headers
        scheme, token = request.headers["Authorization"]&.split(" ", 2)
        Rails.logger.debug("[LlamaBot] auth header = #{scheme.inspect} #{token&.slice(0,8)}…")
        return false unless scheme == AUTH_SCHEME && token.present?
  
        Rails.application.message_verifier(:llamabot_ws).verify(token)
        true
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        false
      end
  
      private
  
      # --------------------------------------------------------------------
      # Automatic check for LlamaBot requests
      # --------------------------------------------------------------------
      def check_agent_authentication
        # Jobs don’t have a request object, so skip token logic there
        return if is_a?(ActiveJob::Base)
  
        has_permitted_actions = self.class.respond_to?(:llama_bot_permitted_actions)
        return unless has_permitted_actions
  
        is_llama_request      = llama_bot_request?
        action_is_whitelisted = self.class.llama_bot_permitted_actions.include?(action_name)
  
        if is_llama_request
          unless action_is_whitelisted
            Rails.logger.warn("[LlamaBot] Action '#{action_name}' isn't white-listed for LlamaBot.")
            render json: { error: "Action '#{action_name}' isn't white-listed for LlamaBot." },
                   status: :forbidden
          end
        elsif action_is_whitelisted
          Rails.logger.warn("[LlamaBot] Action '#{action_name}' requires LlamaBot authentication.")
          render json: { error: "Action '#{action_name}' requires LlamaBot authentication" },
                 status: :forbidden
        end
      end
  
      # --------------------------------------------------------------------
      # Unified guard — browser OR agent
      # --------------------------------------------------------------------
      def devise_user_signed_in?
        return false unless defined?(Devise)
        return false unless respond_to?(:request) && request&.env
        request.env["warden"]&.authenticated?
      end
  
      def authenticate_user_or_agent!(*)
        return if devise_user_signed_in?             # any logged-in Devise scope
  
        if llama_bot_request?
          scheme, token = request.headers["Authorization"]&.split(" ", 2)
          data = Rails.application.message_verifier(:llamabot_ws).verify(token)
  
          allowed = self.class.respond_to?(:llama_bot_permitted_actions) &&
                    self.class.llama_bot_permitted_actions.include?(action_name)
  
          if allowed
            user_object = LlamaBotRails.user_resolver.call(data[:user_id])
            unless LlamaBotRails.sign_in_method.call(request.env, user_object)
              head :unauthorized
            end
            return                                   # ✅ token + allow-listed action
          else
            Rails.logger.warn("[LlamaBot] Action '#{action_name}' isn't white-listed for LlamaBot.")
            render json: { error: "Action '#{action_name}' isn't white-listed for LlamaBot." },
                   status: :forbidden
            return false
          end
        end
  
        # Fall back to Devise or plain 401
        if defined?(Devise) && respond_to?(:request) && request&.env
          request.env["warden"].authenticate!
        else
          head :unauthorized
        end
      end
    end
  end
  