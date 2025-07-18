module LlamaBotRails
    module AgentAuth
      extend ActiveSupport::Concern
      AUTH_SCHEME = "LlamaBot"
  
      included do
        # Add before_action filter to automatically check agent authentication for LlamaBot requests
        before_action :check_agent_authentication, if: :should_check_agent_auth?
        
        # ------------------------------------------------------------------
        # 1) For every Devise scope, alias authenticate_<scope>! so it now
        #    accepts *either* a logged-in browser session OR a valid agent
        #    token. Existing before/skip filters keep working.
        # ------------------------------------------------------------------
        if defined?(Devise)
          Devise.mappings.keys.each do |scope|
            scope_filter = :"authenticate_#{scope}!"
  
            # Next line is a no-op if the method wasn’t already defined.
            alias_method scope_filter, :authenticate_user_or_agent! \
              if method_defined?(scope_filter)
  
            # Emit a gentle nudge during development
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
          # Store the original method if it exists
          original_authenticate_user = if method_defined?(:authenticate_user!)
            instance_method(:authenticate_user!)
          else
            nil
          end
          
          # Define the new method that calls authenticate_user_or_agent!
          define_method(:authenticate_user!) do |*args|
            authenticate_user_or_agent!(*args)
          end
        end
      end
  
      # --------------------------------------------------------------------
      # Public helper: true if the request carries a *valid* agent token
      # --------------------------------------------------------------------
      def should_check_agent_auth?
        # Skip agent authentication entirely if a Devise user is already signed in
        return false if devise_user_signed_in?
        
        # Only check for LlamaBot requests if no Devise user is signed in
        llama_bot_request?
      end

      def llama_bot_request?
        return false unless request&.headers
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
      # Automatic check for LlamaBot requests - called by before_action filter
      # --------------------------------------------------------------------
      def check_agent_authentication
        # Check if this controller has LlamaBot-aware actions
        has_permitted_actions = self.class.respond_to?(:llama_bot_permitted_actions)
        
        # Skip if controller doesn't use llama_bot_allow at all
        return unless has_permitted_actions
        
        is_llama_request = llama_bot_request?
        action_is_whitelisted = self.class.llama_bot_permitted_actions.include?(action_name)
        
        if is_llama_request
          # If it's a LlamaBot request, only allow whitelisted actions
          unless action_is_whitelisted
            Rails.logger.warn("[LlamaBot] Action '#{action_name}' isn't white-listed for LlamaBot. To fix this, add `llama_bot_allow :#{action_name}` in your controller.")
            render json: { error: "Action '#{action_name}' isn't white-listed for LlamaBot. To fix this, add `llama_bot_allow :#{action_name}` in your controller." }, status: :forbidden
            return
          end
          Rails.logger.debug("[[LlamaBot Debug]] Valid LlamaBot request for action '#{action_name}'")
        elsif action_is_whitelisted
          # If action requires LlamaBot auth but request isn't a LlamaBot request, reject it
          Rails.logger.warn("[LlamaBot] Action '#{action_name}' requires LlamaBot authentication, but request is not a valid LlamaBot request.")
          render json: { error: "Action '#{action_name}' requires LlamaBot authentication" }, status: :forbidden
          return
        end
        
        # All other cases: non-LlamaBot requests to non-whitelisted actions are allowed
      end

      # --------------------------------------------------------------------
      # Unified guard — browser OR agent
      # --------------------------------------------------------------------
      def devise_user_signed_in?
        return false unless defined?(Devise)
        return false unless request&.env
        request.env["warden"]&.authenticated?
      end
  
      def authenticate_user_or_agent!(*)
        return if devise_user_signed_in?  # any logged-in Devise scope

        # 2) LlamaBot token present AND action allowed?
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

            return  # ✅ token + allow-listed action + user found and set properly for rack environment
          else
            # ❌ auth token is valid, but the attempted controller action is not added to the whitelist.
            Rails.logger.warn("[LlamaBot] Action '#{action_name}' isn't white-listed for LlamaBot. To fix this, include LlamaBotRails::ControllerExtensions and add `llama_bot_allow :method` in your controller.")
            render json: { error: "Action '#{action_name}' isn't white-listed for LlamaBot. To fix this, include LlamaBotRails::ControllerExtensions and add `llama_bot_allow :method` in your controller." }, status: :forbidden
            return false
          end
        end

        # Neither path worked — fall back to Devise's normal behaviour and let Devise handle 401
        if defined?(Devise) && request&.env
          request.env["warden"].authenticate!  # 401 or redirect
        else
          head :unauthorized
        end
      end
    end
  end
  