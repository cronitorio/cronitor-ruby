require 'spec_helper'

RSpec.describe Cronitor do
  let(:monitor) { Cronitor.new token: token, opts: monitor_options, code: code }

  it 'has a version number' do
    expect(Cronitor::VERSION).not_to be nil
  end

  context 'sets its config correctly' do
    let(:token) { '1234' }
    let(:monitor_options) { { name: 'My Fancy Monitor' } }
    let(:code) { 'abcd' }

    it 'has the specified API token' do
      expect(monitor.token).to eq '1234'
    end

    it 'has the specified options' do
      expect(monitor.opts[:name]).to eq 'My Fancy Monitor'
    end

    it 'has the specified code' do
      expect(monitor.code).to eq 'abcd'
    end
  end

  context 'external request' do
    it 'tries to make a request w/ Unirest' do
      response = Unirest.get 'http://cronitor.io/'
      expect(response.body).to be_an_instance_of String
    end
  end
end
