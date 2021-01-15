module Cronitor
  class << self
    attr_accessor :api_key, :api_version, :environment, :logger, :config

    def configure(&block)
      block.call(self)
    end
  end

  self.api_key = ENV['CRONITOR_API_KEY']
  self.api_version = ENV['CRONITOR_API_VERSION']
  self.environment = ENV['CRONITOR_ENVIRONMENT']
  self.config = ENV['CRONITOR_CONFIG']
  self.logger = Logger.new(STDOUT)
  self.logger.level = Logger::INFO
end