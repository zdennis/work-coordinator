require "factory_bot"
require "database_cleaner/active_record"
require "work_coordinator"
require "work_coordinator/persistence/active_record_setup"

WorkCoordinator::Persistence.connect!(database: ":memory:")
WorkCoordinator::Persistence.migrate!

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    FactoryBot.find_definitions
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning { example.run }
  end

  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.verify_partial_doubles = true }
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching(:focus)
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand(config.seed)
end
