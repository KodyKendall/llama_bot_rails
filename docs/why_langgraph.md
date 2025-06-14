# Why use LangGraph as the Orchestration Framework?

## TL;DR
We use [LangGraph](https://github.com/langchain-ai/langgraph) because building serious AI agents requires more than just calling an LLM. You need structure, memory, planning, and recoverability. LangGraph gives us all of that -- and Rails gives our agents a real environment to operate in.

LangGraph is the **brain**. Rails is the **body**.

---

## The Problem with Stateless AI

Most AI integrations today follow the same pattern:

```ruby
response = OpenAI::Client.chat(prompt: "What's 2 + 2?")
```

That’s fine for basic completions. But it completely breaks down when you're building:

Multi-step agents
- Tool-using agents
- Stateful applications
- Production workflows

Stateless requests can’t:
- Remember what just happened
- Plan what should happen next
- Retry intelligently if something breaks
- Access context across different tools, files, or user sessions

That’s where LangGraph comes in.

## What is LangGraph?

LangGraph is a stateful, structured framework for agent orchestration. It lets you build agents as directed acyclic graphs (DAGs), (also, with cycles!) where each node can:
- Call an LLM
- Use a tool (e.g., Rails console, DB lookup, file edit)
- Reflect on previous steps
- Store and access memory
- Decide the next step in the plan

LangGraph is built for real software engineering. It's not just "chat" — it's control flow, with memory and state.

### What LangGraph Enables

By pairing LangGraph with Rails, we can now build agents that can:
- Scaffold new models and controllers based on a chat spec
- Reflect on broken tests and fix the code
- Update a view and see it in the browser
- Read the database and plan the next action
- Recover from errors and retry intelligently
- Build, ship, and operate Rails features — like a co-pilot, not a chatbot

This is the difference between a tool and an agent.

### Why Not Just Use a Prompt?

Prompt-only systems:
- Don’t scale to complex behavior
- Are impossible to debug
- Can’t recover from bad outputs
- Can’t isolate steps or cache intermediate state

### LangGraph:
- Gives you clear boundaries
- Makes each step testable
- Supports branching logic and re-entry
- Brings real software engineering principles to AI workflows

## Why We Built llama_bot_rails

llama_bot_rails is our gem that wires LangGraph into Ruby on Rails applications. It provides:
- WebSocket-based communication with a LangGraph backend
- A Rails-native chat UI
- Agent input injection (e.g., current route, user, model state)
- Extensibility via custom injectors, tools, and planners

We noticed Rails devs were either avoiding LangGraph or rolling their own orchestration systems from scratch. We believe LangGraph is the missing piece, and this gem is how you plug it into Rails the right way.

Rails is the best framework for empowering devs to build full-stack web apps -- it's also the best framework for empowering intelligent and capable agents. We believe Ruby on Rails is the ultimate tool to hand over to increasingly capable, custom agents. This Gem allows you to do just that.

## Final Word

LangGraph is the brain. Rails is the body.

This gem is the nervous system connecting the two.

This isn't a chatbot.

This is an intelligent operator for your Rails app.

If you believe Rails is still the best full-stack framework... (it is)
... then it's also the best environment for embodied AI agents.

This gem is the bridge.