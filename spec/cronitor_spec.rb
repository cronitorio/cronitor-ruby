# frozen_string_literal: true

require 'spec_helper'

FAKE_API_KEY = 'fake_api_key'
SAMPLE_YAML_FILE = './spec/support/cronitor.yaml'
BAD_CONFIG_YAML_FILE = './spec/support/bad_config.yaml'

MONITOR = {
  type: 'job',
  key: 'a-test_key',
  schedule: '* * * * *',
  assertions: [
      'metric.duration < 10 seconds'
  ]
}

MONITOR_2 = MONITOR.clone
MONITOR_2[:key] = 'another-test-key'


RSpec.describe Cronitor do

  describe '#configure' do
    it 'sets the api_key, api_version, and env' do
      Cronitor.configure do |cronitor|
        cronitor.api_key = 'foo'
        cronitor.api_version = 'bar'
        cronitor.environment = 'baz'
      end

      expect(Cronitor.api_key).to eq('foo')
      expect(Cronitor.api_version).to eq('bar')
      expect(Cronitor.environment).to eq('baz')
    end
  end

  describe '#ping_url and #monitor_url' do
    let(:env_vars) { ENV }

    before do
      stub_const('ENV', env_vars)
      # We need to reset the ping_url and monitor_url since the previous spec sets them globally
      Cronitor.configure do |cronitor|
        cronitor.ping_url = cronitor.default_ping_url
        cronitor.monitor_url = cronitor.default_monitor_url
      end
    end

    context 'when custom CRONITOR_PING_URL and CRONITOR_MONITOR_URL ENV variables are set' do
      let(:env_vars) do
        ENV.to_hash.merge(
          'CRONITOR_PING_URL' => 'https://ping.com',
          'CRONITOR_MONITOR_URL' => 'https://monitor.com'
        )
      end

      it 'returns the custom Cronitor URLs' do
        expect(Cronitor.ping_url).to eq('https://ping.com')
        expect(Cronitor.monitor_url).to eq('https://monitor.com')
      end
    end

    context 'when no CRONITOR_PING_URL or CRONITOR_MONITOR_URL ENV variables are set' do
      it 'returns the default Cronitor URLs' do
        expect(Cronitor.ping_url).to eq('https://cronitor.link')
        expect(Cronitor.monitor_url).to eq('https://cronitor.io')
      end
    end
  end

  describe 'YAML configuration' do
    before(:all) do
      Cronitor.configure do |cronitor|
        cronitor.api_key = FAKE_API_KEY
      end
    end

    context '#read_config' do
      context 'when no config path is set' do
        it 'raises a configuration exception' do
          Cronitor.config = nil
          expect { Cronitor.read_config() }.to raise_error(Cronitor::ConfigurationError)
        end
      end

      context 'when a valid yaml file is supplied' do
        it 'returns a list of monitors' do
          data = Cronitor.read_config(SAMPLE_YAML_FILE)
          expect(data).to eq YAML.safe_load(File.read(Cronitor.config))
          expect(data.length == 3)
        end
      end

      context 'when an invalid yaml file is supplied' do
        it 'raises an exception' do
          expect { Cronitor.read_config(BAD_CONFIG_YAML_FILE) }.to raise_error(Cronitor::ConfigurationError)
          expect(Cronitor.config).to eq BAD_CONFIG_YAML_FILE
        end
      end
    end

    context '#apply_config' do
      context 'when no config path is set' do
        it 'raises a ConfigurationError' do
          Cronitor.config = nil
          expect{ Cronitor.apply_config() }.to raise_error(Cronitor::ConfigurationError)
        end
      end

      it 'makes a put request with a list of monitors and rollback: false' do
        data = Cronitor.read_config(SAMPLE_YAML_FILE)
        expect(Cronitor::Monitor).to receive(:put)
          .with(monitors: data, format: Cronitor::Monitor::Formats::YAML, rollback: false, timeout: 30)
          .and_return(data)

        Cronitor.apply_config()
      end
    end

    context '#validate_config' do
      context 'when no config path is set' do
        it 'raises a ConfigurationError' do
          Cronitor.config = nil
          expect{ Cronitor.validate_config() }.to raise_error(Cronitor::ConfigurationError)
        end
      end

      it 'makes a put request with a list of monitors and rollback: true' do
        data = Cronitor.read_config(SAMPLE_YAML_FILE)
        expect(Cronitor::Monitor).to receive(:put)
          .with(monitors: data, format: Cronitor::Monitor::Formats::YAML, rollback: true, timeout: 30)
          .and_return(data)
        Cronitor.validate_config()
      end
    end
  end

  describe '#job' do
    context 'when no errors are raise' do
      it 'pings run and complete states' do
        expect_any_instance_of(Cronitor::Monitor).to receive(:ping).with(hash_including(state: 'run')).and_return(true)
        expect_any_instance_of(Cronitor::Monitor).to receive(:ping).with(hash_including(state: 'complete')).and_return(true)

        Cronitor.job 'test-job' do
          puts("I am a test job")
        end
      end
    end

    context "when an error is raised" do
      it 'pings run and fail states' do
        expect_any_instance_of(Cronitor::Monitor).to receive(:ping).with(hash_including(state: 'run')).and_return(true)
        expect_any_instance_of(Cronitor::Monitor).to receive(:ping).with(hash_including(state: 'fail')).and_return(true)

        expect {
          Cronitor.job 'test-job' do
            raise StandardError.new("I am failing")
          end
        }.to raise_error(StandardError)
      end
    end
  end

  describe 'Telemetry API' do

    let(:monitor) { Cronitor::Monitor.new('test-key') }
    let(:valid_params) { {
      message: "hello there",
      metrics: {
          count: 1,
          error_count: 1,
          duration: 100,
      },
      env: "production",
      host: '10-0-0-223',
      series: 'world',
    } }

    ['run', 'complete', 'fail', 'ok'].each do |state|
      context "Ping #{state}" do
        before(:all) do
          Cronitor.configure do |cronitor|
            cronitor.api_key = FAKE_API_KEY
          end
        end

        after(:all) do
          Cronitor.api_key = nil
        end


        it "calls #{state} correctly" do
          expect(HTTParty).to receive(:get).and_return(instance_double(HTTParty::Response, code: 200))
          monitor.ping(state: state)
        end

        it "calls #{state} correctly with all params" do
          query = valid_params.clone
          query.merge({
            state: state,
            metric: ['count:1', 'error_count:1', 'duration:100']
          })
          query.delete(:metrics)

          expect(HTTParty).to receive(:get).with(
            monitor.send(:ping_api_url),
            hash_including({
              query: hash_including(query),
              headers: Cronitor::Monitor::Headers::JSON,
              timeout: 5,
            })
          ).and_return(instance_double(HTTParty::Response, code: 200))

          monitor.ping({state: state}.merge(valid_params))
        end
      end
    end

    context "when no api key is set" do
      it "logs an error to STDOUT" do
        Cronitor.api_key = nil
        expect(Cronitor.logger).to receive(:error)
        monitor.ping()
      end
    end
  end

  describe 'Monitor' do
    before(:all) do
      Cronitor.configure do |cronitor|
        cronitor.api_key = FAKE_API_KEY
      end
    end

    context '#new' do
      it 'has the expected key' do
        expect(Cronitor::Monitor.new('test-key').key).to eq 'test-key'
      end
    end

    context '#put' do
      it 'should create a monitor' do
        expect(HTTParty).to receive(:put).and_return(
          instance_double(HTTParty::Response, code: 200, body: {'monitors': [MONITOR]}.to_json)
        )
        monitor = Cronitor::Monitor.put(key: 'test-job', schedule: '* * * * *', type: 'job')
      end

      it 'should create a set of monitors' do
        expect(HTTParty).to receive(:put).and_return(
          instance_double(HTTParty::Response, code: 200, body: {'monitors': [MONITOR, MONITOR_2]}.to_json)
        )
        monitor = Cronitor::Monitor.put(monitors: [MONITOR, MONITOR_2])
      end

      context 'api validation fails' do
        it 'should return a Cronitor:Error on API validation error ' do
        end
      end
    end
  end

  describe 'functional tests - ', type: 'functional' do
    before(:all) do
      Cronitor.configure do |cronitor|
        cronitor.api_key = ENV['CRONITOR_API_KEY']
        cronitor.config = SAMPLE_YAML_FILE
      end
    end

    it 'Creates a monitor' do
      monitor = Cronitor::Monitor.put(key: 'test-key', schedule: '*/5 * * * *', type: 'job')
      expect(monitor.data[:key]).to eq('test-key')
    end

    it 'Syncs yaml config' do
      Cronitor.apply_config
    end

    it 'Pings a monitor' do
      monitor = Cronitor::Monitor.new('ruby-test-pings')
      monitor.ping
      monitor.ping(state: 'run')
      monitor.ping(state: 'complete', metrics: {duration: 100, error_count:10}, host:'uranus1', message: 'holla')
    end

    it 'Pauses a monitor' do
      monitor = Cronitor::Monitor.new('test-key')
      monitor.pause
      monitor.unpause
    end

    it 'Deletes a monitor' do
      expect(Cronitor::Monitor.delete('test-key')).to be(true)
    end

  end
end

