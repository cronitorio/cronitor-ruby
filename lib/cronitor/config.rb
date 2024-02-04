# frozen_string_literal: true

module Cronitor
  MONITOR_TYPES = [
    TYPE_JOB = 'job',
    TYPE_HEARTBEAT = 'heartbeat',
    TYPE_CHECK = 'check'
  ].freeze
  YAML_KEYS = MONITOR_TYPES.map { |t| "#{t}s" }

  class << self
    attr_accessor :api_key, :api_version, :environment, :logger, :config, :timeout, :ping_timeout, :auto_discover_sidekiq, :ping_url, :monitor_url

    def configure(&block)
      block.call(self)
    end
  end

  self.api_key = ENV.fetch('CRONITOR_API_KEY', nil)
  self.api_version = ENV.fetch('CRONITOR_API_VERSION', nil)
  self.environment = ENV.fetch('CRONITOR_ENVIRONMENT', nil)
  self.timeout = ENV.fetch('CRONITOR_TIMEOUT', nil) || 10
  self.ping_timeout = ENV.fetch('CRONITOR_PING_TIMEOUT', nil) || 5
  self.config = ENV.fetch('CRONITOR_CONFIG', nil)
  self.auto_discover_sidekiq = ENV.fetch('CRONITOR_AUTO_DISCOVER_SIDEKIQ', 'true').casecmp('true').zero? # https://github.com/cronitorio/cronitor-sidekiq
  self.ping_url = ENV.fetch('CRONITOR_PING_URL', 'https://cronitor.link')
  self.monitor_url = ENV.fetch('CRONITOR_MONITOR_URL', 'https://cronitor.io')
  self.logger = Logger.new($stdout)
  logger.level = Logger::INFO
end
