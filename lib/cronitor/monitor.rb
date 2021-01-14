# frozen_string_literal: true
require 'pry'
module Cronitor
  class Monitor
    attr_reader :key, :data, :api_key, :api_version, :env

    @@HEADERS = {
      'Content-Type': 'application/json',
      'User-Agent': 'cronitor-ruby',
      'Cronitor-Version': Cronitor.api_version
    }

    PING_RETRY_THRESHOLD = 5

    def self.put(monitors=nil, kwargs={})
      api_key = kwargs[:api_key] || Cronitor.api_key
      kwargs.delete(:api_key)

      rollback = kwargs[:rollback] || false
      kwargs.delete(:rollback)

      @@HEADERS['Cronitor-Version'] = kwargs[:api_version]
      kwargs.delete(:api_version)

      monitors = monitors || [kwargs]
      resp = HTTParty.put(
        Cronitor.monitor_api_url,
        basic_auth: {
          username: api_key,
          password: ''
        },
        body: {
          monitors: monitors,
          rollback: rollback
        }.to_json,
        headers: @@HEADERS,
        timeout: 10
      )

      if resp.code == 200
        _monitors = []
        (resp.body[:monitors]||[]).each do |md|
          self._symbolize_keys(md)
          m = Monitor.new(md[:key])
          m.data = md
          _monitors << m
        end
        return _monitors.length == 1 ? _monitors[0] : _monitors
      elsif resp.code == 400
        raise ValidationError.new(resp.body)
      else
        raise Error.new("Error connecting to Cronitor: #{resp.code}")
      end
    end

    def self.delete(key)
      resp = HTTParty.delete(
        "#{self.monitor_api_url}/key",
        timeout: 10,
        basic_auth: {
          username: Cronitor.api_key,
          password: ''
        },
        headers: @@HEADERS
      )
      resp.code == 200
    end

    def initialize(key, api_key: nil, api_version: nil, env: nil)
      @key = key
      @api_key = api_key || Cronitor.api_key
      @env = env || Cronitor.environment
      @@HEADERS['Cronitor-Version'] = api_version if api_version
    end

    def data
      return @data if defined?(@data)
      data = fetch
      data
    end

    def data=(data)
      @data = data
    end

    def ping(params = {})
      retry_count = params[:retry_count] || 0
      if api_key.nil?
        Cronitor.logger.error("No API key detected. Set Cronitor.api_key or initialize Monitor with an api_key:")
        return false
      end

      begin
        ping_url = ping_api_url
        if retry_count > PING_RETRY_THRESHOLD/2
          ping_url = fallback_ping_api_url
        end

        response = HTTParty.get(
          ping_url,
          query: clean_params(params),
          timeout: 5,
          headers: @@HEADERS,
          query_string_normalizer: -> (query) {
            query.compact!
            metrics = query[:metric]
            query.delete(:metric)
            out = query.map{|k, v| "#{k}=#{v}"}
            out += metrics.map{|m| "metric=#{m}"} if !metrics.nil?
            out.join('&')
          }
          # query_string_normalizer for metrics. instead of metric[]=foo:1 we want metric=foo:1
      )
        if response.code != 200
          Cronitor.logger.error("Cronitor Telemetry Error: #{response.code}")
          return false
        end
        return true
      rescue StandardError => e
        # rescue instances of StandardError i.e. Timeout::Error, SocketError, etc
        Cronitor.logger.error("Cronitor Telemetry Error: #{e}")
        return false if retry_count >= PING_RETRY_THRESHOLD
        # apply a backoff before sending the next ping
        sleep(retry_count * 1.5 * rand)
        ping(params.merge(retry_count: params[:retry_count]+1))
      end
    end

    def ok
      ping(state: 'ok')
    end

    def pause(hours=nil)
      resp = HTTParty.get("#{monitor_api_url}/pause#{hours ? '/' + hours : ''}")
      resp.code == 200
    end

    def unpause
      pause(0)
    end


    private

    def fetch
      if !api_key
        raise Cronitor::Error("No API key detected. Set Cronitor.api_key or initialize Monitor with the api_key kwarg")
      end

      resp = HTTParty.get(monitor_api_url, timeout: 10, headers: @@HEADERS, format: :json)
      self._symbolize_keys(resp.body)
    end

    def clean_params(params)
      {
          state: params.fetch(:state, nil),
          message: params.fetch(:message, nil),
          series: params.fetch(:series, nil),
          host: params.fetch(:host, Socket.gethostname),
          metric: params[:metrics] ? params[:metrics].map{|k, v| "#{k}:#{v}"} : nil,
          stamp: Time.now.to_f,
          env: params.fetch(:env, env)
      }
    end

    def ping_api_url
      "https://cronitor.link/p/#{api_key}/#{key}"
    end

    def fallback_ping_api_url
      "https://cronitor.io/p/#{api_key}/#{key}"
    end

    def monitor_api_url
      "#{Cronitor.monitor_api_url}/{key}"
    end

    def self._symbolize_keys(hash)
      hash.each_with_object({}) do |(k, v), h|
        h[k.to_sym] = v.is_a?(Hash) ? self._symbolize_keys(v) : v
      end
    end
  end
end