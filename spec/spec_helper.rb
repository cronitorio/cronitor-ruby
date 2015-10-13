$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'cronitor'
require 'webmock/rspec'
require 'support/fake_cronitor'
WebMock.disable_net_connect! allow_localhost: true

RSpec.configure do |config|
  config.before(:each) do
    stub_request(:any, /cronitor.(io|link)/).to_rack FakeCronitor
  end

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
  Kernel.srand config.seed
end
