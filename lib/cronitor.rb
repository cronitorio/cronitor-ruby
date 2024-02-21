# frozen_string_literal: true

require 'logger'
require 'json'
require 'httparty'
require 'socket'
require 'time'
require 'yaml'

require 'cronitor/config'
require 'cronitor/error'
require 'cronitor/version'
require 'cronitor/monitor'

module Cronitor
  def self.read_config(path = nil)
    Cronitor.config = path || Cronitor.config
    unless Cronitor.config
      raise ConfigurationError.new(
        "Must include a path by setting Cronitor.config or passing a path to read_config e.g. \
        Cronitor.read_config('./cronitor.yaml')"
      )
    end

    conf = YAML.safe_load(File.read(Cronitor.config))
    conf.each do |k, _v|
      raise ConfigurationError.new("Invalid configuration variable: #{k}") unless Cronitor::YAML_KEYS.include?(k)
    end
    conf
  end

  def self.apply_config(rollback: false)
    conf = read_config
    # allow a significantly longer timeout on requests that are sending full yaml config. min 30 seconds.
    timeout = Cronitor.timeout < 30 ? 30 : Cronitor.timeout
    monitors = Monitor.put(monitors: conf, format: Cronitor::Monitor::Formats::YAML, rollback: rollback,
                           timeout: timeout)
    count = 0
    # step through the different monitor types and count up all the returned configurations
    Cronitor::YAML_KEYS.each do |k|
      count += (monitors[k]&.count || 0)
    end
    puts("#{count} monitors #{rollback ? 'validated' : 'synced to Cronitor'}.")
  rescue ValidationError => e
    Cronitor.logger&.error(e)
  end

  def self.validate_config
    apply_config(rollback: true)
  end

  def self.job(key, &block)
    monitor = Monitor.new(key)
    series = Time.now.to_f
    monitor.ping(state: 'run', series: series)

    begin
      block.call
      monitor.ping(state: 'complete', series: series)
    rescue StandardError => e
      monitor.ping(state: 'fail', message: e.message[[0, e.message.length - 1600].max..-1], series: series)
      raise e
    end
  end

end

Cronitor.read_config(Cronitor.config) unless Cronitor.config.nil?
