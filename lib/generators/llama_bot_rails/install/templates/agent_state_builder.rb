module LlamaBotRails
  # This state builder maps to a LangGraph agent state. Most agents will have custom state. 
  # You can create a custom AgentStateBuilder when creating new, custom agents.
  class AgentStateBuilder
    def initialize(params:, context:)
      @params = params
      @context = context
    end
    

    # Warning: Types must match exactly or you'll get Pydantic errors. It's brittle - If these don't match exactly what's in nodes.py LangGraph state pydantic types, (For example, having a null value/None type when it should be a string) it will break the agent.. 
    # So if it doesn't map state types properly from the frontend, it will break. (must be exactly what's defined here).
    # There won't be an exception thrown -- instead, you'll get a pydantic error message showing up in the BaseMessage content field. (In my case, it was a broken ToolMessage, but serializes from the inherited BaseMessage)
    def build 
      {
        message: @params[:message], # Rails param from JS/chat UI. This is the user's message to the agent.
        thread_id: @context[:thread_id], # This is the thread id for the agent. It is used to track the conversation history.
        api_token: @context[:api_token], # This is an authenticated API token for the agent, so that it can authenticate with us. (It may need access to resources on our Rails app, such as the Rails Console.)
        agent_prompt: LlamaBotRails.agent_prompt_text, # System prompt instructions for the agent. Can be customized in config/agent_prompt.txt
        agent_name: "llamabot" # This routes to the appropriate LangGraph agent as defined in LlamaBot/langgraph.json, and enables us to access different agents on our LlamaBot server.
      }
    end
  end
end 