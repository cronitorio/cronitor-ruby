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
  def self.read_config(path = nil, output: false)
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

    return unless output

    monitors = []
    Cronitor::MONITOR_TYPES.each do |t|
      plural_t = "#{t}s"
      to_parse = conf[t] || conf[plural_t] || nil
      next unless to_parse

      unless to_parse.is_a?(Hash)
        raise ConfigurationError.new('A Hash with keys corresponding to monitor keys is expected.')
      end

      to_parse.each do |key, m|
        m['key'] = key
        m['type'] = t
        monitors << m
      end
    end
    conf['monitors'] = monitors
    conf
  end

  def self.apply_config(rollback: false)
    conf = read_config(output: true)
    # allow a significantly longer timeout on requests that are sending full yaml config
    monitors = Monitor.put(monitors: conf.fetch('monitors', []), rollback: rollback, timeout: 30)
    puts("#{monitors.length} monitors #{rollback ? 'validated' : 'synced to Cronitor'}.")
  rescue ValidationError => e
    Cronitor.logger.error(e)
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

  def self.monitor_api_url
    'https://cronitor.io/api/monitors'
  end
end

Cronitor.read_config(Cronitor.config) unless Cronitor.config.nil?
