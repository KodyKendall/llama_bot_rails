# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'

# Load the dummy application
require_relative 'dummy/config/environment'

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

# Add additional requires below this line. Rails is not loaded until this point!
require 'capybara/rails'
require 'capybara/rspec'
require 'selenium-webdriver'
require 'webmock/rspec'

# Configure WebMock to allow connections for feature tests while blocking for unit tests
WebMock.disable_net_connect!(allow_localhost: true)

# Configure Capybara
Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1280,720')
  
  # Set Chrome binary path for macOS
  if File.exist?('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
    options.binary = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  end
  
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.default_driver = :rack_test
Capybara.javascript_driver = :selenium_chrome_headless
Capybara.default_max_wait_time = 5

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = ["#{::Rails.root}/spec/fixtures"]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  
  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods

  # Include ActionCable test helpers
  config.include ActionCable::TestHelper, type: :channel

  # Set the default path for specs
  config.default_path = 'spec'

  # Configure LlamaBotRails for testing
  config.before(:each) do
    Rails.application.config.llama_bot_rails ||= ActiveSupport::OrderedOptions.new
    Rails.application.config.llama_bot_rails.llamabot_api_url = "http://localhost:8000"
    Rails.application.config.llama_bot_rails.websocket_url = "ws://localhost:8000/ws"
    Rails.application.config.llama_bot_rails.enable_console_tool = true
    Rails.application.config.llama_bot_rails.state_builder_class = "LlamaBotRails::AgentStateBuilder"
  end

  # Configure WebMock for different test types
  config.before(:each, type: :feature) do
    WebMock.allow_net_connect!
  end

  config.after(:each, type: :feature) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end 