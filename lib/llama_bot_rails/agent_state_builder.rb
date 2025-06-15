module LlamaBotRails
    class AgentStateBuilder
      def initialize(params:, context:)
        @params = params
        @context = context
      end
  
      def build
        {
          user_message: @params[:message], # Rails param from JS/chat UI
          thread_id: @context[:thread_id],
          api_token: @context[:api_token],
          agent_name: "llamabot" #Very important. This routes to the appropriate LangGraph agent as defined in langgraph.json
        }
      end
    end
  end