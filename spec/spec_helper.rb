$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'cronitor'
require 'webmock/rspec'
require 'support/fake_cronitor'
WebMock.disable_net_connect! allow_localhost: true

RSpec.configure do |config|
  config.before(:each) do
    stub_request(:any, /cronitor.io/).to_rack FakeCronitor
  end
end
