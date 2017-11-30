require 'sinatra/base'

class FakeCronitor < Sinatra::Base
  class << self
    attr_accessor :last_request
  end

  get '/v1/monitors/:id' do
    if ['efgh', 'Test Cronitor'].include? params['id']
      return json_response 200, 'existing_monitor'
    end

    json_response 404
  end

  post '/v1/monitors' do
    payload = JSON.parse request.body.read
    # Check that we have the necessary payload values very simply
    %w(name rules notifications).each do |k|
      return json_response 400, "invalid_no_#{k}" unless payload.key? k
    end
    json_response 200, 'new_monitor'
  end

  %w(run complete fail).each do |ping|
    get "/abcd/#{ping}" do
      200
    end
  end

  before do
    # Store last request here so rspec an inspect request, specifically for ping msg param
    self.class.last_request = request
  end

  private

  def json_response(response_code, file_name = nil)
    content_type :json
    status response_code
    return '{"detail":"Not found"}' if response_code == 404
    File.open("#{File.dirname __FILE__}/fixtures/#{file_name}.json", 'rb').read
  end
end
