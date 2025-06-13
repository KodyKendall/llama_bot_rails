Gem::Specification.new do |spec|
  require_relative "lib/llama_bot_rails/version"
  spec.name        = "llama_bot_rails"
  spec.version     = LlamaBotRails::VERSION
  spec.authors     = [ "Kody Kendall" ]
  spec.email       = [ "kody@llamapress.ai" ]
  spec.homepage    = "https://llamapress.ai"
  spec.summary     = "LlamaBotRails is a gem that turns your existing Rails App into an AI Agent by connecting it to an open source LangGraph agent, LlamaBot."
  spec.description = "LlamaBotRails is a gem that turns your existing Rails App into an AI Agent by connecting it to an open source LangGraph agent, LlamaBot."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "bin/*"]
  end
  
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "actioncable", "~> 7.0"
  spec.add_dependency "async-websocket"
  spec.add_dependency "async-http"
end
