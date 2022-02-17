# frozen_string_literal: true

module Cronitor
  MONITOR_TYPES = [
    TYPE_JOB = 'job',
    TYPE_HEARTBEAT = 'heartbeat',
    TYPE_CHECK = 'check'
  ].freeze
  YAML_KEYS = MONITOR_TYPES.map { |t| "#{t}s" }

  class << self
    attr_accessor :api_key, :api_version, :environment, :logger, :config, :timeout, :ping_timeout, :_headers

    def configure(&block)
      block.call(self)
    end
  end

  self.api_key = ENV['CRONITOR_API_KEY']
  self.api_version = ENV['CRONITOR_API_VERSION']
  self.environment = ENV['CRONITOR_ENVIRONMENT']
  self.timeout = ENV['CRONITOR_TIMEOUT'] || 10
  self.ping_timeout = ENV['CRONITOR_PING_TIMEOUT'] || 5
  self.config = ENV['CRONITOR_CONFIG']
  self.logger = Logger.new($stdout)
  logger.level = Logger::INFO
  self._headers = {
    'Content-Type': 'application/json',
    'User-Agent': 'cronitor-ruby',
    'Cronitor-Version': Cronitor.api_version
  }
end
