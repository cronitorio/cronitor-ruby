# frozen_string_literal: true

require 'cronitor/version'
require 'cronitor/error'
require 'json'
require 'net/http'
require 'uri'

class Cronitor
  attr_accessor :opts, :code
  API_URL = 'https://cronitor.io/v3'
  PING_URL = 'https://cronitor.link'

  class << self
    attr_accessor :token
  end

  def initialize(token: ENV['CRONITOR_TOKEN'], opts: {}, code: nil)
    self.class.token ||= token
    @opts = opts
    @code = code

    if self.class.token.nil? && @code.nil?
      raise(
        Cronitor::Error,
        'Either a Cronitor API token or an existing monitor code must be ' \
        'provided'
      )
    end

    if @opts
      @opts = symbolize_keys @opts

      exists? @opts[:name] if @opts.key? :name

      # README: Per Cronitor API v2, we need to specify a type. The "heartbeat"
      #         type corresponds to what the v1 API offered by default
      #         We allow other values to be injected, and let the API handle
      #         any errors.
      @opts[:type] = 'heartbeat' unless @opts[:type]
    end

    create if @code.nil?
  end

  def create
    uri = URI.parse "#{API_URL}/monitors"

    http = Net::HTTP.new uri.host, uri.port
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new uri.path, default_headers
    request.basic_auth self.class.token, nil
    request.content_type = 'application/json'
    request.body = JSON.generate opts

    response = http.request request

    @code = JSON.parse(response.body).fetch 'code' if valid? response
  end

  def exists?(name)
    uri = URI.parse "#{API_URL}/monitors/#{URI.escape name}"

    http = Net::HTTP.new uri.host, uri.port
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Get.new uri.path, default_headers
    request.basic_auth self.class.token, nil

    response = http.request request

    return false unless response.is_a? Net::HTTPSuccess

    @code = JSON.parse(response.body).fetch 'code'
    @opts = JSON.parse(response.body)

    true
  end

  def ping(type, msg = nil)
    uri = URI.parse "#{PING_URL}/#{URI.escape code}/#{URI.escape type}"
    if %w[run complete fail].include?(type) && !msg.nil?
      uri.query = URI.encode_www_form 'msg' => msg
    end

    http = Net::HTTP.new uri.host, uri.port
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Get.new uri, default_headers

    response = http.request request

    valid? response
  end

  private

  def valid?(response)
    return true if response.is_a? Net::HTTPSuccess

    msg = if response.content_type.match? 'json'
            error_msg JSON.parse(response.body)
          else
            "Something else has gone awry. HTTP status: #{response.code}"
          end

    raise Cronitor::Error, msg
  end

  def error_msg(body, msg = [])
    body.each do |opt, value|
      if value.respond_to? 'each'
        value.each do |error_msg|
          msg << "#{opt}: #{error_msg}"
        end
      else
        msg << "#{opt}: #{value}"
      end
    end

    msg.join ' '
  end

  def default_headers
    { 'Accept' => 'application/json' }
  end

  def symbolize_keys(hash)
    hash.each_with_object({}) do |(k, v), h|
      h[k.to_sym] = v.is_a?(Hash) ? symbolize_keys(v) : v
    end
  end
end
