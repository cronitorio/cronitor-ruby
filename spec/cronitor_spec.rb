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
        cronitor.telemetry_domain = 'https://ping.com'
      end

      expect(Cronitor.api_key).to eq('foo')
      expect(Cronitor.api_version).to eq('bar')
      expect(Cronitor.environment).to eq('baz')
      expect(Cronitor.telemetry_domain).to eq('https://ping.com')
    end
  end

  describe 'Headers' do
    it 'includes the current api_version in json headers' do
      Cronitor.api_version = '2025-11-28'
      headers = Cronitor::Monitor::Headers.json
      expect(headers[:'Cronitor-Version']).to eq('2025-11-28')
    end

    it 'updates when api_version changes after initial configuration' do
      Cronitor.api_version = 'v1'
      expect(Cronitor::Monitor::Headers.json[:'Cronitor-Version']).to eq('v1')
      Cronitor.api_version = 'v2'
      expect(Cronitor::Monitor::Headers.json[:'Cronitor-Version']).to eq('v2')
    end

    it 'returns yaml headers with correct content type' do
      headers = Cronitor::Monitor::Headers.yaml
      expect(headers[:'Content-Type']).to eq('application/yaml')
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

    context '#generate_config' do
      let(:yaml_content) { "jobs:\n  test-job:\n    schedule: '* * * * *'\n" }
      let(:temp_config_path) { './spec/temp_cronitor.yaml' }
      let(:default_config_path) { './cronitor.yaml' }

      after(:each) do
        File.delete(temp_config_path) if File.exist?(temp_config_path)
        File.delete(default_config_path) if File.exist?(default_config_path)
        Cronitor.config = nil # Reset config to avoid test interference
      end

      context 'when no config path is set' do
        it 'uses default path ./cronitor.yaml' do
          Cronitor.config = nil
          expect(Cronitor::Monitor).to receive(:as_yaml).and_return(yaml_content)
          expect(File).to receive(:open).with('./cronitor.yaml', 'w').and_call_original

          # Mock the file write to avoid creating actual file
          allow(File).to receive(:open).with('./cronitor.yaml', 'w').and_yield(StringIO.new)

          result = Cronitor.generate_config
          expect(result).to be_nil
        end
      end

      context 'when config path is provided' do
        it 'uses the provided path' do
          expect(Cronitor::Monitor).to receive(:as_yaml).and_return(yaml_content)

          result = Cronitor.generate_config(temp_config_path)

          expect(result).to be_nil
          expect(File.exist?(temp_config_path)).to be(true)
          expect(File.read(temp_config_path)).to eq(yaml_content)
        end
      end

      context 'when Cronitor.config is set' do
        it 'uses Cronitor.config path' do
          Cronitor.config = temp_config_path
          expect(Cronitor::Monitor).to receive(:as_yaml).and_return(yaml_content)

          result = Cronitor.generate_config

          expect(result).to be_nil
          expect(File.exist?(temp_config_path)).to be(true)
          expect(File.read(temp_config_path)).to eq(yaml_content)
        end
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
              headers: Cronitor::Monitor::Headers.json,
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

    context "when a custom ping domain is set" do
      it "uses the custom domain in the ping request" do
        Cronitor.telemetry_domain = 'ping.com'
        Cronitor.api_key = FAKE_API_KEY
        expect(HTTParty).to receive(:get).with(
          "https://ping.com/p/#{FAKE_API_KEY}/test-key",
          hash_including({
            headers: Cronitor::Monitor::Headers.json,
            timeout: 5,
          })
        ).and_return(instance_double(HTTParty::Response, code: 200))
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

    context '#as_yaml' do
      let(:yaml_response) { "jobs:\n  test-job:\n    schedule: '* * * * *'\n" }

      it 'should fetch YAML configuration from API' do
        expect(HTTParty).to receive(:get).with(
          'https://cronitor.io/api/monitors.yaml',
          hash_including(
            basic_auth: { username: FAKE_API_KEY, password: '' },
            headers: hash_including('Content-Type': 'application/yaml'),
            timeout: 10
          )
        ).and_return(instance_double(HTTParty::Response, code: 200, body: yaml_response))

        result = Cronitor::Monitor.as_yaml
        expect(result).to eq(yaml_response)
      end

      it 'should use custom API key when provided' do
        custom_api_key = 'custom_key'
        expect(HTTParty).to receive(:get).with(
          'https://cronitor.io/api/monitors.yaml',
          hash_including(
            basic_auth: { username: custom_api_key, password: '' }
          )
        ).and_return(instance_double(HTTParty::Response, code: 200, body: yaml_response))

        Cronitor::Monitor.as_yaml(api_key: custom_api_key)
      end

      it 'should use custom API version when provided' do
        api_version = '2023-01-01'
        expect(HTTParty).to receive(:get).with(
          'https://cronitor.io/api/monitors.yaml',
          hash_including(
            headers: hash_including(:'Cronitor-Version' => api_version)
          )
        ).and_return(instance_double(HTTParty::Response, code: 200, body: yaml_response))

        Cronitor::Monitor.as_yaml(api_version: api_version)
      end

      context 'when no API key is available' do
        it 'raises an error' do
          original_api_key = Cronitor.api_key
          Cronitor.api_key = nil

          expect { Cronitor::Monitor.as_yaml }.to raise_error(Cronitor::Error, /No API key detected/)

          Cronitor.api_key = original_api_key
        end
      end

      context 'when API returns an error' do
        it 'raises an error with the response details' do
          expect(HTTParty).to receive(:get).and_return(
            instance_double(HTTParty::Response, code: 400, body: 'Bad Request')
          )

          expect { Cronitor::Monitor.as_yaml }.to raise_error(Cronitor::Error, /Unexpected error 400: Bad Request/)
        end
      end
    end

    context '#data' do
      it 'should fetch the monitor with cronitor api key' do
        expect(HTTParty).to receive(:get).with("https://cronitor.io/api/monitors", hash_including(basic_auth: {username: Cronitor.api_key, password: ''})).and_return(
          instance_double(HTTParty::Response, code: 200, body: MONITOR.to_json)
        )
        Cronitor::Monitor.new('test-job').data
      end

      context 'when monitor api key is provided' do
        it 'should fetch the monitor with monitor api key' do
          api_key = 'monitor_api_key'
          expect(HTTParty).to receive(:get).with("https://cronitor.io/api/monitors", hash_including(basic_auth: {username: api_key, password: ''})).and_return(
            instance_double(HTTParty::Response, code: 200, body: MONITOR.to_json)
          )
          Cronitor::Monitor.new('test-job', api_key: api_key).data
        end
      end
    end
  end

  describe 'Badge' do
    before(:all) do
      Cronitor.configure do |cronitor|
        cronitor.api_key = FAKE_API_KEY
      end
    end

    let(:sample_badge_response) do
      {
        'production' => {
          'svg' => 'https://cronitor.io/badges/abc123/production/badge-key-1.svg',
          'url' => 'https://cronitor.io/badges/abc123/production/badge-key-1'
        },
        'loyalty-42' => {
          'svg' => 'https://cronitor.io/badges/abc123/production/loyalty-badge-key.svg',
          'url' => 'https://cronitor.io/badges/abc123/production/loyalty-badge-key'
        },
        'qma-99' => {
          'svg' => 'https://cronitor.io/badges/abc123/production/qma-badge-key.svg',
          'url' => 'https://cronitor.io/badges/abc123/production/qma-badge-key'
        }
      }
    end

    context '.all' do
      it 'fetches all badges from the API' do
        expect(HTTParty).to receive(:get).with(
          'https://cronitor.io/api/badges',
          hash_including(
            basic_auth: { username: FAKE_API_KEY, password: '' },
            headers: hash_including('Content-Type': 'application/json')
          )
        ).and_return(instance_double(HTTParty::Response, code: 200, body: sample_badge_response.to_json))

        badges = Cronitor::Badge.all
        expect(badges).to be_a(Hash)
        expect(badges.keys).to contain_exactly('production', 'loyalty-42', 'qma-99')
      end

      it 'returns Badge objects with correct attributes' do
        expect(HTTParty).to receive(:get).and_return(
          instance_double(HTTParty::Response, code: 200, body: sample_badge_response.to_json)
        )

        badges = Cronitor::Badge.all
        badge = badges['production']

        expect(badge).to be_a(Cronitor::Badge)
        expect(badge.tag).to eq('production')
        expect(badge.svg_url).to eq('https://cronitor.io/badges/abc123/production/badge-key-1.svg')
        expect(badge.url).to eq('https://cronitor.io/badges/abc123/production/badge-key-1')
      end

      it 'uses custom api_key when provided' do
        custom_key = 'custom_api_key'
        expect(HTTParty).to receive(:get).with(
          'https://cronitor.io/api/badges',
          hash_including(basic_auth: { username: custom_key, password: '' })
        ).and_return(instance_double(HTTParty::Response, code: 200, body: sample_badge_response.to_json))

        Cronitor::Badge.all(api_key: custom_key)
      end

      it 'uses custom api_version when provided' do
        api_version = '2024-01-01'
        expect(HTTParty).to receive(:get).with(
          'https://cronitor.io/api/badges',
          hash_including(headers: hash_including('Cronitor-Version': api_version))
        ).and_return(instance_double(HTTParty::Response, code: 200, body: sample_badge_response.to_json))

        Cronitor::Badge.all(api_version: api_version)
      end

      context 'when no API key is available' do
        it 'raises an error' do
          original_api_key = Cronitor.api_key
          Cronitor.api_key = nil

          expect { Cronitor::Badge.all }.to raise_error(Cronitor::Error, /No API key detected/)

          Cronitor.api_key = original_api_key
        end
      end

      context 'when API returns an error' do
        it 'raises an error with response details' do
          expect(HTTParty).to receive(:get).and_return(
            instance_double(HTTParty::Response, code: 401, body: 'Unauthorized')
          )

          expect { Cronitor::Badge.all }.to raise_error(Cronitor::Error, /Error fetching badges: 401/)
        end
      end

      context 'when API returns empty response' do
        it 'returns an empty hash' do
          expect(HTTParty).to receive(:get).and_return(
            instance_double(HTTParty::Response, code: 200, body: {}.to_json)
          )

          badges = Cronitor::Badge.all
          expect(badges).to eq({})
        end
      end
    end

    context '#initialize' do
      it 'sets tag, svg_url, and url' do
        badge = Cronitor::Badge.new(
          tag: 'test-tag',
          svg_url: 'https://example.com/badge.svg',
          url: 'https://example.com/badge'
        )

        expect(badge.tag).to eq('test-tag')
        expect(badge.svg_url).to eq('https://example.com/badge.svg')
        expect(badge.url).to eq('https://example.com/badge')
      end

      it 'uses url as fallback for svg_url when svg_url is nil' do
        badge = Cronitor::Badge.new(tag: 'test', url: 'https://example.com/badge')

        expect(badge.svg_url).to eq('https://example.com/badge')
      end

      it 'uses svg_url as fallback for url when url is nil' do
        badge = Cronitor::Badge.new(tag: 'test', svg_url: 'https://example.com/badge.svg')

        expect(badge.url).to eq('https://example.com/badge.svg')
      end
    end

    context '#key' do
      it 'extracts badge key from standard svg_url' do
        badge = Cronitor::Badge.new(
          tag: 'test',
          svg_url: 'https://cronitor.io/badges/abc123/production/my-badge-key.svg'
        )

        expect(badge.key).to eq('my-badge-key')
      end

      it 'extracts badge key from detailed badge svg_url' do
        badge = Cronitor::Badge.new(
          tag: 'test',
          svg_url: 'https://cronitor.io/badges/abc123/production/my-badge-key/detailed.svg'
        )

        expect(badge.key).to eq('my-badge-key')
      end

      it 'returns nil when svg_url is nil' do
        badge = Cronitor::Badge.new(tag: 'test')

        expect(badge.key).to be_nil
      end

      it 'returns nil when svg_url does not match expected pattern' do
        badge = Cronitor::Badge.new(
          tag: 'test',
          svg_url: 'https://example.com/some-other-url.svg'
        )

        expect(badge.key).to be_nil
      end

      it 'handles badge keys with hyphens and underscores' do
        badge = Cronitor::Badge.new(
          tag: 'test',
          svg_url: 'https://cronitor.io/badges/abc/production/my_badge-key_123.svg'
        )

        expect(badge.key).to eq('my_badge-key_123')
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
      monitor = Cronitor::Monitor.new('test-key')
      expect(monitor.delete).to be(true)
    end

  end
end

