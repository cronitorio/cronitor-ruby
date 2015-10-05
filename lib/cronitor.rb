require 'cronitor/version'
require 'net/http'
require 'unirest'

class Cronitor
  attr_accessor :token, :opts, :code

  def initialize(token: nil, opts: {}, code: nil)
    @token = token
    @opts = opts
    @code = code
  end
end
