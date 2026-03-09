require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
require 'webmock/rspec'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_path = "#{::Rails.root}/spec/fixtures"
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  
  # FactoryBot configuration
  config.include FactoryBot::Syntax::Methods
  
  # WebMock configuration
  WebMock.disable_net_connect!(allow_localhost: true)
  
  config.before(:each) do
    # Reset WebMock stubs before each test
    WebMock.reset!
  end
  
  config.after(:each) do
    # Clean up any test data
    DatabaseCleaner.clean if defined?(DatabaseCleaner)
  end
end
