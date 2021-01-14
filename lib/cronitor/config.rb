module Cronitor
  class << self
    attr_accessor :api_key, :api_version, :environment, :logger, :config

    api_key = ENV['CRONITOR_API_KEY']
    api_version = ENV['CRONITOR_API_VERSION']
    environment = ENV['CRONITOR_ENVIRONMENT']
    config = ENV['CRONITOR_CONFIG']
    logger = Logger.new(STDOUT)

    def configure(&block)
      block.call(self)
    end
  end
end