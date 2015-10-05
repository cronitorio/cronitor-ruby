require 'spec_helper'

describe Cronitor do
  it 'has a version number' do
    expect(Cronitor::VERSION).not_to be nil
  end

  context 'sets its config correctly' do
    before(:context) do
      @monitor = Cronitor.new(
        token: '1234',
        opts: { name: 'My Fancy Monitor' },
        code: 'abcd')
    end

    it 'has the specified API token' do
      expect(@monitor.token).to eq '1234'
    end

    it 'has the specified options' do
      expect(@monitor.opts[:name]).to eq 'My Fancy Monitor'
    end

    it 'has the specified code' do
      expect(@monitor.code).to eq 'abcd'
    end
  end
end
