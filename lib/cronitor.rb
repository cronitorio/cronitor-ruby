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
require 'cronitor/ingest'
require 'cronitor/capture'
require 'cronitor/monitor'
require 'cronitor/error_tracking'

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
    timeout = [Cronitor.timeout, 30].max
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

  def self.generate_config(path = nil)
    config_path = path || Cronitor.config || './cronitor.yaml'
    yaml_content = Monitor.as_yaml

    File.open(config_path, 'w') do |file|
      file.write(yaml_content)
    end

    puts("Configuration saved to #{config_path}")
  end

  def self.capture_exception(exception = nil, monitor: nil, series: nil, level: 'error',
                             tags: nil, extra: nil, fingerprint: nil)
    Capture.capture_exception(
      exception,
      monitor: monitor,
      series: series,
      level: level,
      tags: tags,
      extra: extra,
      fingerprint: fingerprint
    )
  end

  def self.capture_message(message, level: 'info', monitor: nil, series: nil,
                           tags: nil, extra: nil, fingerprint: nil)
    Capture.capture_message(
      message,
      level: level,
      monitor: monitor,
      series: series,
      tags: tags,
      extra: extra,
      fingerprint: fingerprint
    )
  end

  def self.flush(timeout: 2.0)
    Ingest.flush(timeout: timeout)
  end

  def self.safe_ping(monitor, params)
    monitor.ping(params)
  rescue StandardError => e
    Cronitor.logger&.warn("Cronitor could not send the #{params[:state]} ping for #{monitor.key}: #{e}")
    false
  end

  def self.job(key, capture_exceptions: nil, &block)
    monitor = Monitor.new(key)
    series = Time.now.to_f
    safe_ping(monitor, state: 'run', series: series)
    token = Capture.bind_job(key, series, monitor.env)

    begin
      result = block.call
      safe_ping(monitor, state: 'complete', series: series)
      result
    rescue StandardError => e
      message = e.message.to_s
      safe_ping(monitor, state: 'fail', message: message[[0, message.length - 1600].max..-1], series: series)
      should_capture = capture_exceptions.nil? ? Cronitor.capture_exceptions : capture_exceptions
      if should_capture && !Ingest.parse_dsn(Cronitor.dsn).nil?
        Capture._capture_exception(
          e,
          monitor: key,
          series: series,
          env: monitor.env,
          mechanism: 'cronitor.job',
          handled: false
        )
      end
      raise e
    ensure
      Capture.unbind_job(token)
    end
  end
end

Cronitor.read_config(Cronitor.config) unless Cronitor.config.nil?
