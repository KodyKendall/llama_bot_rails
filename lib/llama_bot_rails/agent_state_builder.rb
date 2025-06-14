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
          agent_name: "llamabot" #routes to the LangGraph agent in langgraph.json
        }
      end
    end
  end