# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cronitor'

RSpec.configure do |config|
  config.filter_run_excluding type: 'functional' if ENV['CRONITOR_API_KEY'].nil?

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!

  config.default_formatter = 'doc' if config.files_to_run.one?
  config.order = :random
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
  Kernel.srand config.seed
end
