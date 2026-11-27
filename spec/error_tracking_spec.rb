# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'zlib'
require 'stringio'

RSpec.describe 'Cronitor Error Tracking' do
  let(:test_dsn) { 'https://ing_test123@cronitor.link/1' }
  let(:envelope_url) { 'https://cronitor.link/api/1/envelope/' }
  let(:test_api_key) { 'rest_api_key_123' }

  around do |example|
    saved = {
      api_key: Cronitor.api_key,
      api_version: Cronitor.api_version,
      environment: Cronitor.environment,
      dsn: Cronitor.dsn,
      release: Cronitor.release,
      capture_exceptions: Cronitor.capture_exceptions,
      logger: Cronitor.logger,
      config: Cronitor.config
    }
    previous_transport = Cronitor::Ingest.set_transport(Cronitor::Ingest::Transport.new)
    Cronitor.logger = Logger.new(StringIO.new)
    Cronitor.dsn = nil
    Cronitor.release = nil
    Cronitor.environment = nil
    Cronitor.capture_exceptions = true
    Cronitor.api_key = test_api_key
    Cronitor.api_version = nil

    example.run
  ensure
    Cronitor.flush(timeout: 1.0)
    Cronitor::Ingest.set_transport(previous_transport)
    saved.each { |k, v| Cronitor.public_send("#{k}=", v) }
    WebMock.reset!
  end

  def decode_envelope(gzipped_body)
    raw = Zlib::GzipReader.new(StringIO.new(gzipped_body)).read
    lines = raw.split("\n")
    {
      headers: JSON.parse(lines[0]),
      item_headers: JSON.parse(lines[1]),
      payload: JSON.parse(lines[2])
    }
  end

  describe 'DSN parsing' do
    it 'parses a standard DSN' do
      expect(Cronitor::Ingest.parse_dsn('https://ing_abc123@cronitor.link/1')).to eq(
        ['ing_abc123', 'https://cronitor.link/api/1/envelope/', 'https://ing_abc123@cronitor.link/1']
      )
    end

    it 'ignores trailing slashes' do
      expect(Cronitor::Ingest.parse_dsn('https://ing_abc123@cronitor.link/42/')).to eq(
        ['ing_abc123', 'https://cronitor.link/api/42/envelope/', 'https://ing_abc123@cronitor.link/42']
      )
    end

    it 'supports custom host and port' do
      expect(Cronitor::Ingest.parse_dsn('http://dev_key@localhost:9100/1')).to eq(
        ['dev_key', 'http://localhost:9100/api/1/envelope/', 'http://dev_key@localhost:9100/1']
      )
    end

    it 'strips optional secret from public DSN' do
      expect(Cronitor::Ingest.parse_dsn('https://pub_key:secret@cronitor.link/42')).to eq(
        ['pub_key', 'https://cronitor.link/api/42/envelope/', 'https://pub_key@cronitor.link/42']
      )
    end

    it 'defaults missing project path to 1' do
      expect(Cronitor::Ingest.parse_dsn('https://ing_abc123@cronitor.link')).to eq(
        ['ing_abc123', 'https://cronitor.link/api/1/envelope/', 'https://ing_abc123@cronitor.link/1']
      )
    end

    it 'returns nil for empty or invalid DSNs' do
      [nil, '', '   ', 'not-a-dsn', 'ftp://key@cronitor.link/1', 'https://cronitor.link/1', 123].each do |bad|
        expect(Cronitor::Ingest.parse_dsn(bad)).to be_nil
      end
    end
  end

  describe 'gzipped envelope transport' do
    it 'sends gzipped Sentry envelope with expected headers and no Authorization header' do
      Cronitor.dsn = 'https://ing_test123:ignored_secret@cronitor.link/1'
      Cronitor.api_key = 'secret_rest_api_key'
      Cronitor.release = '5.4.0'
      Cronitor.environment = 'production'

      captured_req = nil
      stub = stub_request(:post, envelope_url).to_return do |req|
        captured_req = req
        { status: 200, body: '{}' }
      end

      event_id = Cronitor.capture_message('hello world', level: 'warn')
      expect(event_id).to match(/\A[0-9a-f]{32}\z/)
      expect(Cronitor.flush(timeout: 2.0)).to be(true)
      expect(stub).to have_been_requested.once

      expect(captured_req.headers['Content-Type']).to eq('application/x-sentry-envelope')
      expect(captured_req.headers['Content-Encoding']).to eq('gzip')
      expect(captured_req.headers['User-Agent']).to eq('cronitor-ruby')
      expect(captured_req.headers['X-Sentry-Auth']).to eq(
        "Sentry sentry_key=ing_test123, sentry_version=7, sentry_client=cronitor-ruby/#{Cronitor::VERSION}"
      )
      expect(captured_req.headers).not_to have_key('Authorization')

      decoded = decode_envelope(captured_req.body)
      expect(decoded[:headers]['event_id']).to eq(event_id)
      expect(decoded[:headers]['dsn']).to eq('https://ing_test123@cronitor.link/1')
      expect(decoded[:headers]['sdk']).to eq('name' => 'cronitor-ruby', 'version' => Cronitor::VERSION)
      expect(decoded[:item_headers]['type']).to eq('event')
      expect(decoded[:item_headers]['content_type']).to eq('application/json')
      expect(decoded[:payload]['level']).to eq('warning')
      expect(decoded[:payload]['platform']).to eq('ruby')
      expect(decoded[:payload]['release']).to eq('5.4.0')
      expect(decoded[:payload]['environment']).to eq('production')
    end

    it 'does not fall back to api_key when dsn is missing' do
      Cronitor.dsn = nil
      Cronitor.api_key = 'rest_api_key_only'

      event_id = Cronitor.capture_message('should not send')
      expect(event_id).to be_nil
      expect(Cronitor.flush(timeout: 1.0)).to be(true)
      expect(WebMock).not_to have_requested(:any, /cronitor/)
    end

    it 'swallows HTTP 500 and 429 transport failures without raising' do
      Cronitor.dsn = test_dsn
      stub_request(:post, envelope_url).to_return(
        { status: 500, body: 'server error' },
        { status: 429, headers: { 'Retry-After' => '30' }, body: 'rate limited' }
      )

      expect(Cronitor.capture_message('first')).to be_a(String)
      expect(Cronitor.capture_message('second')).to be_a(String)
      expect(Cronitor.flush(timeout: 2.0)).to be(true)

      expect(Cronitor.capture_message('dropped while rate limited')).to be_a(String)
      expect(Cronitor.flush(timeout: 2.0)).to be(true)
      expect(WebMock).to have_requested(:post, envelope_url).twice
    end
  end

  describe 'capture_exception' do
    it 'captures exception with backtrace, source context, and cause chain' do
      Cronitor.dsn = test_dsn
      captured_body = nil
      stub_request(:post, envelope_url).to_return do |req|
        captured_body = req.body
        { status: 200, body: '{}' }
      end

      event_id = nil
      begin
        begin
          raise ArgumentError, 'root cause'
        rescue ArgumentError
          raise RuntimeError, 'outer failure'
        end
      rescue RuntimeError
        event_id = Cronitor.capture_exception(monitor: 'nightly-sync', tags: { region: 'us-east-1' })
      end

      expect(event_id).to be_a(String)
      expect(Cronitor.flush(timeout: 2.0)).to be(true)

      payload = decode_envelope(captured_body)[:payload]
      expect(payload['tags']['cronitor.monitor']).to eq('nightly-sync')
      expect(payload['tags']['region']).to eq('us-east-1')

      values = payload['exception']['values']
      expect(values.length).to eq(2)
      expect(values[0]['type']).to eq('ArgumentError')
      expect(values[0]['value']).to eq('root cause')
      expect(values[1]['type']).to eq('RuntimeError')
      expect(values[1]['value']).to eq('outer failure')

      frames = values[1]['stacktrace']['frames']
      expect(frames).not_to be_empty
      last_frame = frames.last
      expect(last_frame['filename']).to include('error_tracking_spec.rb')
      expect(last_frame['lineno']).to be_a(Integer)
      expect(last_frame['context_line']).to include('outer failure')
      expect(last_frame['in_app']).to be(true)
    end

    it 'returns nil when called with no exception outside rescue' do
      Cronitor.dsn = test_dsn
      expect(Cronitor.capture_exception).to be_nil
    end

    it 'supports monitor-bound capture without raising' do
      Cronitor.dsn = test_dsn
      captured_body = nil
      stub_request(:post, envelope_url).to_return do |req|
        captured_body = req.body
        { status: 200, body: '{}' }
      end

      monitor = Cronitor::Monitor.new('billing-job', env: 'staging')
      event_id = monitor.capture_exception(StandardError.new('charge failed'))
      expect(event_id).to be_a(String)
      expect(Cronitor.flush(timeout: 2.0)).to be(true)

      payload = decode_envelope(captured_body)[:payload]
      expect(payload['tags']['cronitor.monitor']).to eq('billing-job')
      expect(payload['environment']).to eq('staging')
    end
  end

  describe 'capture_message' do
    it 'captures message with fingerprint, extra, and strict JSON for non-finite floats' do
      Cronitor.dsn = test_dsn
      captured_body = nil
      stub_request(:post, envelope_url).to_return do |req|
        captured_body = req.body
        { status: 200, body: '{}' }
      end

      event_id = Cronitor.capture_message(
        'Disk 90% full',
        level: 'critical',
        tags: { host: 'worker-1' },
        extra: { mount: '/var', ratio: Float::NAN, limit: Float::INFINITY },
        fingerprint: 'disk-space-warning'
      )

      expect(event_id).to be_a(String)
      expect(Cronitor.flush(timeout: 2.0)).to be(true)

      payload = decode_envelope(captured_body)[:payload]
      expect(payload).not_to have_key('exception')
      expect(payload['level']).to eq('fatal')
      expect(payload['message']).to eq('formatted' => 'Disk 90% full')
      expect(payload['fingerprint']).to eq(['disk-space-warning'])
      expect(payload['extra']['mount']).to eq('/var')
      expect(payload['extra']['ratio']).to eq('NaN')
      expect(payload['extra']['limit']).to eq('Infinity')
    end

    it 'accepts array fingerprints' do
      Cronitor.dsn = test_dsn
      captured_body = nil
      stub_request(:post, envelope_url).to_return do |req|
        captured_body = req.body
        { status: 200, body: '{}' }
      end

      Cronitor.capture_message('grouped', fingerprint: %w[import timeout])
      expect(Cronitor.flush(timeout: 2.0)).to be(true)

      payload = decode_envelope(captured_body)[:payload]
      expect(payload['fingerprint']).to eq(%w[import timeout])
    end
  end

  describe 'Cronitor.job integration' do
    before do
      allow_any_instance_of(Cronitor::Monitor).to receive(:ping).and_return(true)
    end

    it 'auto-captures unhandled exceptions and re-raises the original exception' do
      Cronitor.dsn = test_dsn
      captured_body = nil
      stub = stub_request(:post, envelope_url).to_return do |req|
        captured_body = req.body
        { status: 200, body: '{}' }
      end

      expect do
        Cronitor.job('nightly-import') do
          raise StandardError, 'db timeout'
        end
      end.to raise_error(StandardError, 'db timeout')

      expect(Cronitor.flush(timeout: 2.0)).to be(true)
      expect(stub).to have_been_requested.once

      payload = decode_envelope(captured_body)[:payload]
      expect(payload['tags']['cronitor.monitor']).to eq('nightly-import')
      expect(payload['tags']['cronitor.series']).not_to be_nil
      exc = payload['exception']['values'].last
      expect(exc['mechanism']).to eq('type' => 'cronitor.job', 'handled' => false)
    end

    it 'returns the block result on success' do
      result = Cronitor.job('ok-job') { 42 }
      expect(result).to eq(42)
    end

    it 'supports per-call opt-out via capture_exceptions: false' do
      Cronitor.dsn = test_dsn
      stub = stub_request(:post, envelope_url).to_return(status: 200, body: '{}')

      expect do
        Cronitor.job('opt-out-job', capture_exceptions: false) do
          raise StandardError, 'ignored'
        end
      end.to raise_error(StandardError, 'ignored')

      expect(Cronitor.flush(timeout: 1.0)).to be(true)
      expect(stub).not_to have_been_requested
    end

    it 'supports global opt-out via Cronitor.capture_exceptions = false' do
      Cronitor.dsn = test_dsn
      Cronitor.capture_exceptions = false
      stub = stub_request(:post, envelope_url).to_return(status: 200, body: '{}')

      expect do
        Cronitor.job('global-opt-out') { raise StandardError, 'ignored' }
      end.to raise_error(StandardError, 'ignored')

      expect(Cronitor.flush(timeout: 1.0)).to be(true)
      expect(stub).not_to have_been_requested
    end

    it 'skips auto-capture when no usable DSN is configured' do
      Cronitor.dsn = nil
      expect(Cronitor::Capture).not_to receive(:_capture_exception)

      expect do
        Cronitor.job('no-dsn-job') { raise StandardError, 'still re-raised' }
      end.to raise_error(StandardError, 'still re-raised')
    end
  end

  describe 'Cronitor.flush' do
    it 'returns false when the worker does not drain before timeout' do
      gate = Queue.new
      slow_transport = Cronitor::Ingest::Transport.new(
        send: lambda do |_url, _data, _headers, _timeout|
          gate.pop
          Struct.new(:code, :headers).new(200, {})
        end
      )
      Cronitor::Ingest.set_transport(slow_transport)
      Cronitor.dsn = test_dsn

      expect(Cronitor.capture_message('slow')).to be_a(String)
      expect(Cronitor.flush(timeout: 0.05)).to be(false)

      gate.push(:release)
      expect(Cronitor.flush(timeout: 2.0)).to be(true)
    end
  end

  describe 'ErrorApp and ErrorGroup REST resources' do
    it 'creates, lists, updates, rotates key, and deletes an ErrorApp' do
      stub_request(:post, 'https://cronitor.io/api/error-apps')
        .with(
          basic_auth: [test_api_key, ''],
          body: { name: 'Billing API' }.to_json
        )
        .to_return(
          status: 201,
          body: { key: 'app_123', name: 'Billing API', dsn: 'https://ing_1@cronitor.link/1' }.to_json
        )

      app = Cronitor::ErrorApp.create(name: 'Billing API')
      expect(app.key).to eq('app_123')
      expect(app.dsn).to eq('https://ing_1@cronitor.link/1')

      stub_request(:patch, 'https://cronitor.io/api/error-apps/app_123')
        .with(body: { name: 'Payments API' }.to_json)
        .to_return(
          status: 200,
          body: { key: 'app_123', name: 'Payments API', dsn: 'https://ing_1@cronitor.link/1' }.to_json
        )

      app.update(name: 'Payments API')
      expect(app.name).to eq('Payments API')

      stub_request(:post, 'https://cronitor.io/api/error-apps/app_123/rotate-key')
        .to_return(
          status: 200,
          body: { key: 'app_123', name: 'Payments API', dsn: 'https://ing_2@cronitor.link/1' }.to_json
        )

      rotated = app.rotate_key
      expect(rotated).to equal(app)
      expect(app.dsn).to eq('https://ing_2@cronitor.link/1')

      stub_request(:delete, 'https://cronitor.io/api/error-apps/app_123')
        .to_return(status: 204, body: '')

      expect(app.delete).to be(true)
    end

    it 'auto-paginates ErrorApp.list and guards against non-positive page_size' do
      stub_request(:get, 'https://cronitor.io/api/error-apps')
        .with(query: { page: '1', pageSize: '2' })
        .to_return(status: 200, body: { error_apps: [{ key: 'app_1' }, { key: 'app_2' }] }.to_json)
      stub_request(:get, 'https://cronitor.io/api/error-apps')
        .with(query: { page: '2', pageSize: '2' })
        .to_return(status: 200, body: { error_apps: [{ key: 'app_3' }] }.to_json)

      apps = Cronitor::ErrorApp.list(page: 1, page_size: 2, auto_paginate: true)
      expect(apps.map(&:key)).to eq(%w[app_1 app_2 app_3])

      zero_stub = stub_request(:get, 'https://cronitor.io/api/error-apps')
                  .with(query: { page: '1', pageSize: '50' })
                  .to_return(status: 200, body: { apps: Array.new(50) { |i| { key: "app_#{i}" } } }.to_json)

      guarded = Cronitor::ErrorApp.list(page_size: 0, auto_paginate: true)
      expect(guarded.length).to eq(50)
      expect(zero_stub).to have_been_requested.once
    end

    it 'does not loop on fractional or non-finite page_size with auto_paginate' do
      expect(Cronitor::ErrorTrackingAPI.positive_page_size?(0.5)).to be(false)
      expect(Cronitor::ErrorTrackingAPI.positive_page_size?(Float::INFINITY)).to be(false)
      expect(Cronitor::ErrorTrackingAPI.positive_page_size?(Float::NAN)).to be(false)
      expect(Cronitor::ErrorTrackingAPI.normalize_page_size(0.5)).to eq(50)
      expect(Cronitor::ErrorTrackingAPI.normalize_page_size(Float::INFINITY)).to eq(50)

      app_stub = stub_request(:get, 'https://cronitor.io/api/error-apps')
                 .with(query: { page: '1', pageSize: '50' })
                 .to_return(status: 200, body: { apps: Array.new(50) { |i| { key: "app_#{i}" } } }.to_json)

      apps = Cronitor::ErrorApp.list(page_size: 0.5, auto_paginate: true)
      expect(apps.length).to eq(50)
      expect(app_stub).to have_been_requested.once

      group_stub = stub_request(:get, 'https://cronitor.io/api/errors')
                   .with(query: { 'page' => '1', 'pageSize' => '50' })
                   .to_return(status: 200, body: { errors: Array.new(50) { |i| { key: "err_#{i}" } } }.to_json)

      groups = Cronitor::ErrorGroup.list(page_size: 0.5, auto_paginate: true)
      expect(groups.length).to eq(50)
      expect(group_stub).to have_been_requested.once
    end

    it 'raises ErrorAppNotFound on 404' do
      stub_request(:get, 'https://cronitor.io/api/error-apps/missing')
        .to_return(status: 404, body: 'Not Found')

      expect { Cronitor::ErrorApp.new('missing').data }.to raise_error(Cronitor::ErrorAppNotFound)
    end

    it 'lists, fetches, updates ErrorGroups and retrieves events' do
      stub_request(:get, 'https://cronitor.io/api/errors')
        .with(
          query: {
            'app' => 'app_123',
            'env' => 'production',
            'status' => 'open',
            'end' => '2026-01-02T00:00:00Z',
            'orderBy' => 'last_seen',
            'page' => '1',
            'pageSize' => '25'
          }
        )
        .to_return(
          status: 200,
          body: { errors: [{ key: 'err_1', title: 'ZeroDivisionError' }] }.to_json
        )

      groups = Cronitor::ErrorGroup.list(
        app: 'app_123',
        env: 'production',
        status: 'open',
        end: '2026-01-02T00:00:00Z',
        order_by: 'last_seen',
        page_size: 25
      )
      expect(groups.length).to eq(1)
      expect(groups.first.key).to eq('err_1')

      stub_request(:patch, 'https://cronitor.io/api/errors/err_1')
        .with(body: { status: 'resolved', env: 'production' }.to_json)
        .to_return(status: 200, body: { key: 'err_1', status: 'resolved' }.to_json)

      group = Cronitor::ErrorGroup.new('err_1')
      group.update(status: 'resolved', env: 'production')
      expect(group.data[:status]).to eq('resolved')

      stub_request(:get, 'https://cronitor.io/api/errors/err_1/events')
        .with(query: { 'limit' => '10', 'env' => 'production' })
        .to_return(status: 200, body: { data: [{ event_id: 'evt_1' }] }.to_json)

      events = group.events(env: 'production', limit: 10)
      expect(events['data'].first['event_id']).to eq('evt_1')

      stub_request(:get, 'https://cronitor.io/api/errors/err_1/events/evt_1')
        .to_return(status: 200, body: { event_id: 'evt_1', level: 'error' }.to_json)

      event = group.event('evt_1')
      expect(event['event_id']).to eq('evt_1')
    end

    it 'raises ErrorGroupNotFound on 404' do
      stub_request(:get, 'https://cronitor.io/api/errors/missing')
        .to_return(status: 404, body: 'Not Found')

      expect { Cronitor::ErrorGroup.new('missing').data }.to raise_error(Cronitor::ErrorGroupNotFound)
    end
  end

  describe 'errors monitor type and YAML config' do
    it 'accepts errors as a top-level YAML key in read_config' do
      data = Cronitor.read_config('./spec/support/cronitor.yaml')
      expect(data['errors']).to have_key('billing-error-spikes')
      expect(data['errors']['billing-error-spikes']['window']).to eq('5m')
    end

    it 'supports type: errors in Monitor.put' do
      error_monitor = {
        type: 'errors',
        key: 'new-billing-errors',
        trigger: 'new',
        apps: ['app_0123456789abcdef'],
        notify: ['devops-alerts-slack']
      }
      stub_request(:put, 'https://cronitor.io/api/monitors')
        .with(body: { monitors: [error_monitor], rollback: false }.to_json)
        .to_return(status: 200, body: { monitors: [error_monitor] }.to_json)

      monitor = Cronitor::Monitor.put(error_monitor)
      expect(monitor.key).to eq('new-billing-errors')
      expect(monitor.data[:type]).to eq('errors')
    end
  end
end
