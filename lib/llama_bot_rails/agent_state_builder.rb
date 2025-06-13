module LlamaBotRails
    class AgentStateBuilder
      def initialize(params:, context:)
        @params = params
        @context = context
      end
  
      def build
        {
          user_message: @params[:message], # Rails param from JS/chat UI
          thread_id: @context[:thread_id].nil? ? "global_thread_id" : @context[:thread_id], #thread_id is for memory & long-term state persistence
          agent_name: "llamabot" #routes to the LangGraph agent in langgraph.json
        }
      end
    end
  end