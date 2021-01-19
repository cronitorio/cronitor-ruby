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

  def self.monitor_api_url
    "https://cronitor.io/api/monitors"
  end

  def self.TYPE_JOB
    'job'
  end

  def self.TYPE_EVENT
    'event'
  end

  def self.TYPE_SYNTHETIC
    'synthetic'
  end

  def self.MONITOR_TYPES
    [self.TYPE_JOB, self.TYPE_EVENT, self.TYPE_SYNTHETIC]
  end

  def self.read_config(path=nil, output: false)
    Cronitor.config = path || Cronitor.config
    unless Cronitor.config
        raise ConfigurationError.new(
          "Must include a path by setting Cronitor.config or passing a path to read_config e.g. Cronitor.read_config('./cronitor.yaml')"
        )
    end

    conf = YAML.load(File.read(Cronitor.config))
    conf.each do |k, v|
      raise ConfigurationError.new("Invalid configuration variable: #{k}") unless self.YAML_KEYS.include?(k)
    end

    Cronitor.api_key     = conf[:api_key] if conf[:api_key]
    Cronitor.api_version = conf[:api_version] if conf[:api_version]
    Cronitor.environment = conf[:environment] if conf[:environment]

    return unless output

    monitors = []
    self.MONITOR_TYPES.each do |t|
      plural_t = "#{t}s"
      to_parse = conf[t] || conf[plural_t] || nil
      return unless to_parse

      if !to_parse.is_a?(Hash)
        raise ConfigurationError.new("A Hash with keys corresponding to monitor keys is expected.")
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
    begin
      conf = self.read_config(output: true)
      monitors = Monitor.put(monitors: conf.fetch('monitors', []), rollback: rollback)
      puts("#{monitors.length} monitors #{rollback ? 'validated' : 'synced to Cronitor'}.")
    rescue ValidationError => e
      Cronitor.logger.error(e)
    end
  end

  def self.validate_config
    apply_config(rollback: true)
  end

  def self.job(key, &block)
    monitor = Monitor.new(key)
    series = Time.now.to_f
    monitor.ping(state: 'run', series: series)

    begin
      out = block.call
      monitor.ping(state: 'complete', series: series)
    rescue Exception => e
      monitor.ping(state: 'fail', message: e.message[[0, e.message.length-1600].max..-1], series: series)
      raise e
    end
  end


  def self.YAML_KEYS
    [
      'api_key',
      'api_version',
      'environment'
    ] + self.MONITOR_TYPES.map{|t| "#{t}s" }
  end
end

Cronitor.read_config(Cronitor.config) if !Cronitor.config.nil?
