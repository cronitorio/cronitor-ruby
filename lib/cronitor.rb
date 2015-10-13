require 'cronitor/version'
require 'cronitor/error'
require 'net/http'
require 'unirest'

Unirest.default_header 'Accept', 'application/json'
Unirest.default_header 'Content-Type', 'application/json'

class Cronitor
  attr_accessor :token, :opts, :code
  API_URL = 'https://cronitor.io/v1'

  def initialize(token: nil, opts: {}, code: nil)
    @token = token
    @opts = opts
    @code = code

    # TODO Update this to allow for tokenless usage w/ a code for an already
    # created monitor
    fail Cronitor::Error, 'Missing Cronitor API token' if token.nil?

    create if code.nil?
  end

  def create
    response = Unirest.post(
      "#{API_URL}/monitors",
      auth: { user: token },
      parameters: opts.to_json
    )

    validate response
    @code = response.body['code']
  end

  def validate(response)
    return if [200, 201].include? response.code
    server_error? response

    fail Cronitor::Error, error_msg(response.body)
  end

  private

  def error_msg(body)
    msg = []

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
    return unless [301, 302, 500, 502, 503, 504].include? response.code

    fail(
      Cronitor::Error,
      "Something else has gone awry. HTTP status: #{response.code}"
    )
  end
end
