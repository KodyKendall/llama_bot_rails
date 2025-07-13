module LlamaBotRails
    module AgentAuth
      extend ActiveSupport::Concern
      AUTH_SCHEME = "LlamaBot"
  
      included do
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
          alias_method :authenticate_user!, :authenticate_user_or_agent! \
            if method_defined?(:authenticate_user!)
        end
      end
  
      # --------------------------------------------------------------------
      # Public helper: true if the request carries a *valid* agent token
      # --------------------------------------------------------------------
      def llama_bot_request?
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
      # Unified guard — browser OR agent
      # --------------------------------------------------------------------
      def devise_user_signed_in?
        return false unless defined?(Devise)
        request.env["warden"]&.authenticated?
      end
  
      def authenticate_user_or_agent!(*)
        return if devise_user_signed_in?  # any logged-in Devise scope

        # 2) LlamaBot token present AND action allowed?
        if llama_bot_request?
            allowed = self.class.respond_to?(:llama_bot_permitted_actions) &&
                    self.class.llama_bot_permitted_actions.include?(action_name)

            return if allowed        # ✅ token + allow-listed action

            Rails.logger.debug("[LlamaBot] Action '#{action_name}' is allowed for LlamaBot.")
            Rails.logger.debug("[LlamaBot] self.class.llama_bot_permitted_actions = #{self.class.llama_bot_permitted_actions}")
            Rails.logger.debug("[LlamaBot] self.class.llama_bot_permitted_actions.include?(action_name) = #{self.class.llama_bot_permitted_actions.include?(action_name)}")
            
            # ❌ auth token is valid, but the attempted controller action is not added to the whitelist.
            Rails.logger.warn("[LlamaBot] Action '#{action_name}' isn't white-listed for LlamaBot. To fix this, include LlamaBotRails::ControllerExtensions and add `llama_bot_allow :method` in your controller.")
            render json: { error: "Action '#{action_name}' isn't white-listed for LlamaBot. To fix this, include LlamaBotRails::ControllerExtensions and add `llama_bot_allow :method` in your controller." }, status: :forbidden
            return false
        end
  
        # Neither path worked — fall back to Devise’s normal behaviour and let Devise handle 401
        if defined?(Devise)
          request.env["warden"].authenticate!  # 401 or redirect
        else
          head :unauthorized
        end
      end
    end
  end
  