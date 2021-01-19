# frozen_string_literal: true

module Cronitor
  class << self
    attr_accessor :api_key, :api_version, :environment, :logger, :config, :_headers

    def configure(&block)
      block.call(self)
    end
  end

  self.api_key = ENV['CRONITOR_API_KEY']
  self.api_version = ENV['CRONITOR_API_VERSION']
  self.environment = ENV['CRONITOR_ENVIRONMENT']
  self.config = ENV['CRONITOR_CONFIG']
  self.TYPE_JOB = 'job'
  self.TYPE_EVENT = 'event'
  self.TYPE_SYNTHETIC = 'synthetic'
  self.MONITOR_TYPES = [self.TYPE_JOB, self.TYPE_EVENT, self.TYPE_SYNTHETIC]
  self.YAML_KEYS = %w[
    api_key
    api_version
    environment
  ] + self.MONITOR_TYPES.map { |t| "#{t}s" }

  self.logger = Logger.new($stdout)
  logger.level = Logger::INFO
  self._headers = {
    'Content-Type': 'application/json',
    'User-Agent': 'cronitor-ruby',
    'Cronitor-Version': Cronitor.api_version
  }
end
