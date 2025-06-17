# 🚀 LlamaBotRails

**Turn any Rails app into an AI Agent in 2 minutes**

Chat with a powerful agent that has access to your models, your application context, and can run console commands. All powered by LangGraph + OpenAI.

[![Gem Version](https://badge.fury.io/rb/llama_bot_rails.svg)](https://badge.fury.io/rb/llama_bot_rails)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%202.7-red)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%207.0-red)](https://rubyonrails.org/)

---

## 🎥 **See it in action** (30-Second Demo)

<img src="https://llamapress-ai-image-uploads.s3.us-west-2.amazonaws.com/pp1s3l4iskwabnq0gi5tx8mi9mue" width="600" alt="LlamaBot live demo">

### The agent can:

- 🔍 **Explore your Rails app** (models, routes, controllers)
- 💾 **Query and create data** via Rails console
- 🛠️ **Take action on your behalf**
- 🧠 **Understand your domain** through natural conversation


---

## 🚀 **Quickstart** →

```bash

# 1. Add the gem
bundle add llama_bot_rails

# 2. Install the routes & chat interface
rails generate llama_bot_rails:install

# 3. Clone & run the LangGraph backend
git clone https://github.com/kodykendall/llamabot

cd llamabot

# 4. Set up your environment
python3 -m venv venv

source venv/bin/activate

pip install -r requirements.txt

echo "OPENAI_API_KEY=your_openai_api_key_here" > .env

# 5. Run the agent
cd backend
uvicorn app:app --reload

# 6. Confirm our agent is running properly. You should see: Hello, World! 🦙💬
curl http://localhost:8000/hello

# 7. Start your Rails server.
rails server

# 8. Visit the chat interface and start chatting.
open http://localhost:3000/llama_bot/agent/chat

```

**That's it.** ✅ You can now chat with your Rails app like a new assistant.

### Try asking:
- "What models do I have in this app?"
- "Show me the User model structure"
- "Create a test user"
- "What are my routes?"

### Prerequisites
- Rails 7.0+
- Ruby 2.7+  
- Redis (for ActionCable)
- OpenAI API key

---

## 🧨 **Power & Responsibility**

### ⚠️ **This gem gives the agent access to your Rails console.**

This is **incredibly powerful** -- and also potentially dangerous in production.
*Treat it like giving shell access to a developer.*

🚫 **Do not deploy this tool to production** without understanding the risks to your production data & application.

**🛡️ Production safety features coming soon**

## 🏗️ **Architecture**

```
┌────────────────────┐         WebSocket        ┌────────────────────┐
│     Rails App      │ ←──────────────────────→ │     LangGraph      │
│    (Your App)      │                          │  FastAPI (Python)  │
├────────────────────┤                          ├────────────────────┤
│   LlamaBotRails    │                          │   Agents & Tools   │
│        Gem         │                          │    (LangGraph)     │
└────────────────────┘                          └────────────────────┘

```

**What happens:**
1. **Rails frontend** provides a chat interface 
2. **ActionCable WebSocket** handles real-time communication to LangGraph
3. **LangGraph backend** runs the AI agent with access to tools
4. **Agent executes** A sequence of Rails console commands, reasoning throughout the process.
5. **Results stream back** to the chat interface in real-time

## 🛠️ **Customization**

### Custom State Builder

Control what data your agent sees:

```ruby
# config/initializers/llama_bot_rails.rb
class CustomAgentStateBuilder < LlamaBotRails::AgentStateBuilder
  def build
    super.merge({
      current_user: @context[:user]&.to_json,
      app_version: Rails.application.version,
      custom_context: gather_app_context
    })
  end
  
  private
  
  def gather_app_context
    {
      model_count: ActiveRecord::Base.subclasses.count,
      route_count: Rails.application.routes.routes.count,
      environment: Rails.env,
      database_name: ActiveRecord::Base.connection_db_config.database
    }
  end
end

# Configure the gem to use your builder
Rails.application.configure do
  config.llama_bot_rails.state_builder_class = "CustomAgentStateBuilder"
end
```

### Environment Configuration

```ruby
# config/environments/development.rb
Rails.application.configure do
  config.llama_bot_rails.enable_console_tool = true
end

# config/environments/production.rb
Rails.application.configure do
  config.llama_bot_rails.enable_console_tool = false # Disable in production
end
```

## 🧪 **What You Can Build**

### Developer Assistant
- **Code exploration**: "Show me how authentication works"
- **Data analysis**: "How many users signed up this month?" 
- **Quick prototyping**: "Create a basic blog post model"

## 🔧 **Under the Hood**

### Real-Time Communication
- **ActionCable WebSocket** Real-time Rails <-> Agent communication.
- **LangGraph Backend** FastAPI + OpenAI tool orchestration

### Security   
- **Secure channel seperation** -> Per-session isolation.
- **Token expiration** and automatic refresh mechanisms

### Command Streaming
- **`run_rails_console_command`**: Execute Ruby code in Rails context

## 📋 **Requirements**

### Rails Application
- **Rails 7.0+** - Modern Rails version with ActionCable support
- **Ruby 2.7+** - Compatible Ruby version
- **ActionCable configured** - For real-time WebSocket communication
- **Redis** - Recommended for production ActionCable backend

### LangGraph Backend  
- **Python 3.11+** - Python runtime environment
- **FastAPI application** - Web framework for the agent backend
- **OpenAI API access** - For LLM capabilities
- **WebSocket support** - For real-time bidirectional communication

## 🧨 Troubleshooting
- Agent not responding? Check that backend is running and OpenAI key is set.
- WebSocket issues? Confirm LLAMABOT_WEBSOCKET_URL matches backend address.

## 🤝 **Contributing**

We'd love your help making LlamaBotRails better!

### How to Contribute

1. **Fork the repo**
2. **Create a feature branch**: `git checkout -b my-new-feature`
3. **Make your changes** and add tests
4. **Run the test suite**: `bundle exec rspec`
5. **Submit a pull request**

### Development Setup

```bash
# Clone the repo
git clone https://github.com/kodykendall/llama_bot_rails
cd llama_bot_rails

# Install dependencies
bundle install

# Run tests  
bundle exec rspec

# Test in a real Rails app
cd example_app
bundle exec rails server
```

---

## 🌟 **What's Next?**

We're just getting started. Coming soon:

- 🛡️ **Enhanced security controls** for production deployments
- 🔧 **More built-in tools** (scaffolding, API calls, database queries)
- 🎨 **Customizable chat themes** and branding  
- 📊 **Analytics and monitoring** for agent interactions
- 🔌 **Plugin system** for custom tool development
- 🤖 **Multi-agent support** for complex workflows
- 🔄 **Background job integration** for long-running tasks

---

## 📝 **License**

[MIT](https://opensource.org/licenses/MIT). — free for commercial and personal use.

---

## ⭐️ **Support the Project!**

If LlamaBotRails helped you, **give us a star** ⭐️ and **share it** with other Rails developers.

This is just the beginning. Let's build the Rails agentic future -- together.

**[⭐️ Star on GitHub](https://github.com/kodykendall/llama_bot_rails)** • **[🍴 Fork the repo](https://github.com/kodykendall/llama_bot_rails/fork)** • **[💬 Join discussions](https://github.com/kodykendall/llama_bot_rails/discussions)**

---

*Built with ❤️ by [Kody Kendall](https://kodykendall.com)*