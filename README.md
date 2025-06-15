# 🚀 LlamaBotRails

**Turn any Rails app into an AI Agent in 2 minutes**

Chat with your models. Generate pages. Run console commands. All powered by LangGraph + OpenAI.

[![Gem Version](https://badge.fury.io/rb/llama_bot_rails.svg)](https://badge.fury.io/rb/llama_bot_rails)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%202.7-red)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%207.0-red)](https://rubyonrails.org/)

---

## ⭐️ **Try it now in your Rails app** →

```bash
# 1. Add to any Rails app
bundle add llama_bot_rails

# 2. Install the chat interface  
rails generate llama_bot_rails:install

# 3. Clone & run the LangGraph backend
git clone https://github.com/kodykendall/llamabot
cd llamabot
OPENAI_API_KEY=your_key uvicorn app:app

# 4. Visit your app and start chatting
open http://localhost:3000/llama_bot/agent/chat
```

**That's it.** Your Rails app now has an AI agent that understands your models, routes, and codebase.

---

## 🎥 **See it in action** (30 seconds)

### The agent can:

- 🔍 **Explore your Rails app** (models, routes, controllers)
- 💾 **Query and create data** via Rails console
- 🛠️ **Generate code and pages**
- 🧠 **Understand your domain** through natural conversation

## 🧨 **Power & Responsibility**

### ⚠️ **WARNING: Rails Console Tool is Powerful**

The `run_rails_console_command` tool gives the AI agent access to your Rails console.
This is **amazing for local/dev environments**, but dangerous in production.

🚫 **Do not deploy this tool to production** without removing or tightly controlling it.

**To disable it:**
- Remove the tool from `AgentStateBuilder` 
- Or set `LLAMABOT_ENV=production` and conditionally skip dev-only tools

*This is a developer tool first — treat it like you'd treat giving someone console access.*

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
1. **Rails frontend** provides a modern chat interface  
2. **ActionCable WebSocket** handles real-time communication
3. **LangGraph backend** runs the AI agent with access to tools
4. **Agent executes** Rails console commands and returns results
5. **Results stream back** to your chat interface in real-time

## 🚀 **Quick Start**

### Prerequisites
- Rails 7.0+
- Ruby 2.7+  
- Redis (for ActionCable in production)
- OpenAI API key

### 1. Install the Gem

```ruby
# Gemfile
gem 'llama_bot_rails'
```

```bash
bundle install
```

### 2. Generate the Chat Interface
```bash
rails generate llama_bot_rails:install
```

This adds:
- Routes (/llama_bot/agent/chat)
- ActionCable channel configuration
- Chat interface views
- JavaScript assets

### 3. Set Up the LangGraph Backend
```bash
# Clone the LangGraph agent
git clone https://github.com/kodykendall/llamabot
cd llamabot

# Install Python dependencies  
pip install -r requirements.txt

# Set your OpenAI API key
export OPENAI_API_KEY=your_openai_api_key_here

# Run the backend
uvicorn app:app --host 0.0.0.0 --port 8000
```

### 4. Start Chatting
```bash
# Start your Rails server
rails server

# Visit the chat interface
open http://localhost:3000/llama_bot/agent/chat
```

Try asking:
- "What models do I have in this app?"
- "Show me the User model structure"
- "Create a test user"
- "What are my routes?"

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

Set up your environment variables:

```bash
# .env
LLAMABOT_WEBSOCKET_URL=ws://localhost:8000/ws
DEVELOPMENT_ENVIRONMENT=true
OPENAI_API_KEY=your_openai_api_key_here

# For production
LLAMABOT_WEBSOCKET_URL=wss://your-llamabot-backend.com/ws
PRODUCTION_ENVIRONMENT=true
```

```ruby
# config/environments/development.rb
Rails.application.configure do
  config.llama_bot_rails.websocket_url = ENV['LLAMABOT_WEBSOCKET_URL']
  config.llama_bot_rails.enable_console_tool = true
end

# config/environments/production.rb
Rails.application.configure do
  config.llama_bot_rails.websocket_url = ENV['LLAMABOT_WEBSOCKET_URL']
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
- **ActionCable WebSocket** for frontend ↔ Rails communication
- **Async WebSocket client** for Rails ↔ LangGraph communication  
- **Message streaming** with connection monitoring and reconnection
- **Connection pooling** and automatic retry logic
- **Bidirectional data flow** with real-time updates

### Security Features  
- **JWT authentication** for agent API access
- **Session-based channel isolation** prevents message crosstalk
- **Request logging** and comprehensive audit trails
- **Environment-aware SSL/TLS** configuration
- **Token expiration** and automatic refresh mechanisms
- **CSRF protection** for all agent endpoints

### Agent Tools & Capabilities
- **`run_rails_console_command`**: Execute Ruby code in Rails context
- **Thread management**: Conversation persistence via LangGraph checkpoints
- **Error handling**: Graceful error display and recovery
- **State management**: Configurable context builders
- **Tool chaining**: Sequential command execution with context
- **Response streaming**: Real-time output as commands execute

### Architecture Components
- **Rails Engine**: Modular integration with existing Rails apps
- **ActionCable Channel**: WebSocket communication layer
- **Agent State Builder**: Customizable context management
- **Message Router**: Intelligent routing between Rails and LangGraph
- **Connection Monitor**: Health checks and reconnection logic

## 📋 **Requirements**

### Rails Application
- **Rails 7.0+** - Modern Rails version with ActionCable support
- **Ruby 2.7+** - Compatible Ruby version
- **ActionCable configured** - For real-time WebSocket communication
- **Redis** - Recommended for production ActionCable backend

### LangGraph Backend  
- **Python 3.8+** - Python runtime environment
- **FastAPI application** - Web framework for the agent backend
- **OpenAI API access** - For LLM capabilities
- **WebSocket support** - For real-time bidirectional communication

### Development Environment
```bash
# Required environment variables
OPENAI_API_KEY=your_openai_api_key_here
LLAMABOT_WEBSOCKET_URL=ws://localhost:8000/ws

# Optional for development
DEVELOPMENT_ENVIRONMENT=true
REDIS_URL=redis://localhost:6379/0
```

### Production Environment  
```bash
# Production requirements
OPENAI_API_KEY=your_production_openai_key
LLAMABOT_WEBSOCKET_URL=wss://your-backend.com/ws
REDIS_URL=your_production_redis_url

# Security settings
RAILS_ENV=production
LLAMABOT_ENV=production
```

### System Dependencies
- **Git** - For cloning the LangGraph backend
- **Node.js** - For JavaScript asset compilation (if using asset pipeline)
- **PostgreSQL/MySQL** - Database for Rails application
- **Redis Server** - For ActionCable in production

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

# Run rubocop for code style
bundle exec rubocop

# Test in a real Rails app
cd example_app
bundle exec rails server
```

### What We're Looking For

- 🐛 **Bug fixes** and error handling improvements
- 🔧 **New tools** for agent capabilities  
- 🎨 **UI/UX improvements** for the chat interface
- 📚 **Documentation** updates and examples
- 🧪 **Test coverage** improvements
- 🛡️ **Security enhancements**

### Development Guidelines

- **Write tests** for all new features
- **Follow Ruby style guide** (we use RuboCop)
- **Update documentation** for any API changes
- **Keep commits focused** and write clear commit messages
- **Test in both development and production** environments

### Getting Help

Need help with your contribution? 

- 💬 **Start a discussion** in [GitHub Discussions](https://github.com/kodykendall/llama_bot_rails/discussions)
- 📧 **Email us** at [kody@llamapress.ai](mailto:kody@llamapress.ai)
- 🐛 **Open an issue** if you find bugs

## 🐛 **Troubleshooting**

### Chat Interface Won't Load
- **Check ActionCable configuration**: Ensure `config/cable.yml` is properly configured
- **Verify Redis**: Make sure Redis is running (required for production)
- **Browser console**: Check for JavaScript errors in browser developer tools
- **Route conflicts**: Ensure `/llama_bot/agent/chat` route isn't conflicting

```bash
# Test ActionCable connection
rails console
ActionCable.server.broadcast("test", message: "hello")
```

### Agent Not Responding  
- **Backend status**: Verify LangGraph backend is running on `localhost:8000`
- **API key**: Check `OPENAI_API_KEY` is set correctly and valid
- **WebSocket errors**: Look for connection errors in Rails logs
- **Network issues**: Test backend connectivity

```bash
# Test backend connectivity
curl http://localhost:8000/health

# Test WebSocket connection
wscat -c ws://localhost:8000/ws
```

### Permission Errors
- **Token validation**: Ensure agent authentication tokens are valid
- **Authorization logs**: Check Rails logs for authorization failures  
- **Session config**: Verify session store configuration
- **CORS issues**: Check cross-origin settings if using different domains

### Common Issues

```bash
# Clear Rails cache
rails tmp:clear

# Restart ActionCable
rails restart

# Check gem installation
bundle list | grep llama_bot_rails

# Verify environment variables
echo $OPENAI_API_KEY
echo $LLAMABOT_WEBSOCKET_URL
```

### Getting Help
- 📖 [**Full Documentation**](https://github.com/kodykendall/llama_bot_rails/wiki)
- 💬 [**GitHub Discussions**](https://github.com/kodykendall/llama_bot_rails/discussions)  
- 🐛 [**Report Issues**](https://github.com/kodykendall/llama_bot_rails/issues)
- 📧 **Email**: [kody@llamapress.ai](mailto:kody@llamapress.ai)

---

## 🌟 **What's Next?**

We're just getting started. Coming soon:

- 🛡️ **Enhanced security controls** for production deployments
- 🔧 **More built-in tools** (file system, API calls, database queries)
- 🎨 **Customizable chat themes** and branding  
- 📊 **Analytics and monitoring** for agent interactions
- 🔌 **Plugin system** for custom tool development
- 🤖 **Multi-agent support** for complex workflows
- 🔄 **Background job integration** for long-running tasks

---

## 📄 **License**

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

## ⭐️ **Star us on GitHub!**

If LlamaBotRails helped you build something cool, **give us a star** ⭐️ and **share it** with other Rails developers!

**[⭐️ Star on GitHub](https://github.com/kodykendall/llama_bot_rails)** • **[🍴 Fork the repo](https://github.com/kodykendall/llama_bot_rails/fork)** • **[💬 Join discussions](https://github.com/kodykendall/llama_bot_rails/discussions)**

---

*Built with ❤️ by the [LlamaPress](https://llamapress.ai) team*