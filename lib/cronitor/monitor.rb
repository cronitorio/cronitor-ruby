# frozen_string_literal: true

module Cronitor
  class Monitor
    attr_reader :key, :api_key, :api_version, :env

    PING_RETRY_THRESHOLD = 3

    module Formats
      ALL = [
        JSON = 'json',
        YAML = 'yaml'
      ].freeze
    end

    module Headers
      JSON = {
        'Content-Type': 'application/json',
        'User-Agent': "cronitor-ruby-#{Cronitor::VERSION}",
        'Cronitor-Version': Cronitor.api_version
      }.freeze
      YAML = JSON.merge({
                          'Content-Type': 'application/yaml'
                        })
    end


    def self.put(opts = {})
      rollback = opts[:rollback] || false
      opts.delete(:rollback)

      monitors = opts[:monitors] || [opts]
      url = "https://cronitor.io/api/monitors"
      if opts[:format] == Cronitor::Monitor::Formats::YAML
        url = "#{url}.yaml"
        monitors['rollback'] = true if rollback
        body = YAML.dump(monitors)
        headers = Cronitor::Monitor::Headers::YAML
      else
        body = {
          monitors: monitors,
          rollback: rollback
        }.to_json
        headers = Cronitor::Monitor::Headers::JSON
      end

      resp = HTTParty.put(
        url,
        basic_auth: {
          username: Cronitor.api_key,
          password: ''
        },
        body: body,
        headers: headers,
        timeout: opts[:timeout] || Cronitor.timeout
      )

      case resp.code
      when 200
        if opts[:format] == Cronitor::Monitor::Formats::YAML
          YAML.safe_load(resp.body)
        else
          out = []
          data = JSON.parse(resp.body)

          (data['monitors'] || []).each do |md|
            m = Monitor.new(md['key'])
            m.data = Cronitor.symbolize_keys(md)
            out << m
          end
          out.length == 1 ? out[0] : out
        end
      when 400
        raise ValidationError.new(resp.body)
      else
        raise Error.new("Error connecting to Cronitor: #{resp.code}\n #{resp.body}")
      end
    end

    def self.delete(key)
      resp = HTTParty.delete(
        "#{Cronitor.monitor_api_url}/#{key}",
        timeout: Cronitor.timeout,
        basic_auth: {
          username: Cronitor.api_key,
          password: ''
        },
        headers: Cronitor::Monitor::Headers::JSON
      )
      if resp.code != 204
        Cronitor.logger&.error("Error deleting monitor: #{key}")
        return false
      end
      true
    end

    def initialize(key, api_key: nil, env: nil)
      @key = key
      @api_key = api_key || Cronitor.api_key
      @env = env || Cronitor.environment
    end

    def data
      return @data if defined?(@data)

      @data = fetch
      @data
    end

    def data=(data)
      @data = Cronitor.symbolize_keys(data)
    end

    def ping(params = {})
      retry_count = params[:retry_count] || 0
      if api_key.nil?
        Cronitor.logger&.error('No API key detected. Set Cronitor.api_key or initialize Monitor with an api_key:')
        return false
      end

      begin
        ping_url = ping_api_url
        ping_url = fallback_ping_api_url if retry_count > PING_RETRY_THRESHOLD
      
        response = HTTParty.get(
          ping_url,
          query: clean_params(params),
          timeout: Cronitor.ping_timeout,
          headers: Cronitor::Monitor::Headers::JSON,
          query_string_normalizer: lambda do |query|
            query.compact!
            metrics = query[:metric]
            query.delete(:metric)
            out = query.map { |k, v| "#{k}=#{v}" }
            out += metrics.map { |m| "metric=#{m}" } unless metrics.nil?
            out.join('&')
          end
          # query_string_normalizer for metrics. instead of metric[]=foo:1 we want metric=foo:1
        )

        if response.code != 200
          Cronitor.logger&.error("Cronitor Telemetry Error: #{response.code}")
          return false
        end
        true
      rescue StandardError => e
        # rescue instances of StandardError i.e. Timeout::Error, SocketError, etc
        Cronitor.logger&.error("Cronitor Telemetry Error: #{e}")
        return false if retry_count >= Monitor::PING_RETRY_THRESHOLD

        # apply a backoff before sending the next ping
        sleep(retry_count * 1.5 * rand)
        ping(params.merge(retry_count: retry_count + 1))
      end
    end

    def ok
      ping(state: 'ok')
    end

    def pause(hours = nil)
      pause_url = "#{monitor_api_url}/#{key}/pause"
      pause_url += "/#{hours}" unless hours.nil?

      resp = HTTParty.get(
        pause_url,
        timeout: Cronitor.timeout,
        headers: Cronitor::Monitor::Headers::JSON,
        basic_auth: {
          username: api_key,
          password: ''
        }
      )
      puts(resp.code)
      resp.code == 200
    end

    def unpause
      pause(0)
    end

    def ping_api_url
      "https://#{Cronitor.telemetry_domain}/p/#{api_key}/#{key}"
    end

    def fallback_ping_api_url
      "https://cronitor.io/p/#{api_key}/#{key}"
    end

    def monitor_api_url
      "https://cronitor.io/api/monitors"
    end


    private

    def fetch
      unless api_key
        Cronitor.logger&.error(
          'No API key detected. Set Cronitor.api_key or initialize Monitor with the api_key kwarg'
        )
        return
      end

      HTTParty.get(monitor_api_url, timeout: Cronitor.timeout, headers: Cronitor::Monitor::Headers::JSON, format: :json)
    end

    def clean_params(params)
      {
        state: params.fetch(:state, nil),
        message: params.fetch(:message, nil),
        series: params.fetch(:series, nil),
        host: params.fetch(:host, Socket.gethostname),
        metric: params[:metrics] ? params[:metrics].map { |k, v| "#{k}:#{v}" } : nil,
        stamp: Time.now.to_f,
        env: params.fetch(:env, env)
      }
    end
  end

  def self.symbolize_keys(obj)
    obj.inject({}) do |memo, (k, v)|
      memo[k.to_sym] = v
      memo
    end
  end
end
