require 'cronitor/version'
require 'cronitor/error'
require 'net/http'
require 'unirest'

Unirest.default_header 'Accept', 'application/json'
Unirest.default_header 'Content-Type', 'application/json'

class Cronitor
  attr_accessor :token, :opts, :code
  API_URL = 'https://cronitor.io/v1'
  PING_URL = 'https://cronitor.link'

  def initialize(token: nil, opts: {}, code: nil)
    @token = token
    @opts = opts
    @code = code

    if @token.nil? && @code.nil?
      fail(
        Cronitor::Error,
        'Either a Cronitor API token or an existing monitor code must be ' \
        'provided'
      )
    end

    if @opts
      exists? @opts[:name] if @opts.key? :name
      human_readable @opts[:rules] if @opts.key? :rules
    end

    create if @code.nil?
  end

  def create
    response = Unirest.post(
      "#{API_URL}/monitors",
      auth: { user: token },
      parameters: opts.to_json
    )

    @code = response.body['code'] if valid? response
  end

  def exists?(name)
    response = Unirest.get(
      "#{API_URL}/monitors/#{URI.escape(name).gsub('[', '%5B').gsub(']', '%5D')}",
      auth: { user: token }
    )
    return false unless response.code == 200

    @code = response.body['code']

    true
  end

  def ping(type, msg = nil)
    url = "#{PING_URL}/#{code}/#{type}"
    url += "?msg=#{URI.escape msg}" if type == 'fail' && !msg.nil?

    response = Unirest.get url
    valid? response
  end

  def human_readable(rules)
    rules.each do |rule|
      unless rule[:human_readable]
        rule[:human_readable] = "#{rule[:rule_type]} #{rule[:duration]} " \
                                "#{rule[:time_unit]}"
      end
    end
  end

  private

  def valid?(response)
    return true if [200, 201].include? response.code
    server_error? response

    fail Cronitor::Error, error_msg(response.body)
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

  def server_error?(response)
    return unless [301, 302, 404, 500, 502, 503, 504].include? response.code

    fail(
      Cronitor::Error,
      "Something else has gone awry. HTTP status: #{response.code}"
    )
  end
end
