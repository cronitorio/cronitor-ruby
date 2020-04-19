# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cronitor do
  let(:token) { '1234' }
  let(:monitor_options) { nil }

  before(:all) { ENV.delete('CRONITOR_TOKEN') }
  before(:each) { described_class.token = nil }

  describe '.token' do
    before do
      described_class.token = token
      allow_any_instance_of(described_class).to receive(:create)
    end

    it 'set token on class' do
      expect(described_class.token).to eq(token)
    end

    it 'reuse class token' do
      expect { subject }.not_to raise_error
    end

    context 'with no class token' do
      let(:token) { nil }

      it 'raise' do
        expect { subject }.to raise_error Cronitor::Error, 'Either a Cronitor API token or an existing monitor code must be ' \
          'provided'
      end
    end
  end

  it 'has a version number' do
    expect(Cronitor::VERSION).not_to be nil
  end

  context 'sets its config correctly' do
    let(:monitor_options) { { name: 'My Fancy Monitor' } }
    let(:code) { 'abcd' }
    let(:monitor) do
      Cronitor.new token: token, opts: monitor_options, code: code
    end

    it 'has the specified API token' do
      expect(monitor.class.token).to eq '1234'
    end

    it 'has the specified options' do
      expect(monitor.opts[:name]).to eq 'My Fancy Monitor'
    end

    it 'has the specified code' do
      expect(monitor.code).to eq 'abcd'
    end
  end

  describe '.new' do
    let(:monitor) { Cronitor.new token: token, opts: monitor_options }

    context 'when a token and all options are provided' do
      let(:monitor_options) do
        {
          name: 'My Fancy Monitor',
          notifications: { emails: ['test@example.com'] },
          rules: [{
            rule_type: 'not_completed_in',
            duration: 5,
            time_unit: 'seconds'
          }],
          note: 'A human-friendly description of this monitor'
        }
      end

      context 'with a token in ENV' do
        before { ENV['CRONITOR_TOKEN'] = token }
        after { ENV.delete('CRONITOR_TOKEN') }

        it 'uses the token from ENV' do
          expect(monitor.class.token).to eql(token)
        end
      end

      context 'when the monitor does not exist' do
        it 'creates a monitor' do
          expect(monitor.code).to eq 'abcd'
        end
      end

      context 'when the monitor already exists' do
        before { monitor_options[:name] = 'Test Cronitor' }

        it "uses the existing monitor's code" do
          expect(monitor.code).to eq 'efgh'
        end
      end
    end

    context 'when a code for a pre-existing monitor is provided' do
      let(:monitor) { Cronitor.new code: 'efgh' }

      it 'uses the existing monitor' do
        expect(monitor.code).to eq 'efgh'
      end
    end

    context 'when token and code are missing' do
      let(:token) { nil }

      it 'raises Cronitor::Error exception' do
        expect { monitor }.to raise_error(
          Cronitor::Error,
          'Either a Cronitor API token or an existing monitor code must be ' \
          'provided'
        )
      end
    end

    context 'when name option is missing' do
      let(:monitor_options) do
        {
          notifications: { emails: ['noone@example.com'] },
          rules: [{
            rule_type: 'not_run_in',
            duration: 5,
            time_unit: 'seconds'
          }]
        }
      end

      it 'raises Cronitor::Error exception' do
        expect { monitor }.to raise_error(
          Cronitor::Error,
          'name: This field is required.'
        )
      end
    end

    context 'when notifications are missing' do
      let(:monitor_options) do
        {
          name: 'My Fancy Monitor',
          rules: [{
            rule_type: 'not_run_in',
            duration: 5,
            time_unit: 'seconds'
          }]
        }
      end

      it 'raises Cronitor::Error exception' do
        expect { monitor }.to raise_error(
          Cronitor::Error,
          'notifications: This field is required.'
        )
      end
    end

    context 'when rules are missing' do
      let(:monitor_options) do
        {
          name: 'My Fancy Monitor',
          notifications: { emails: ['noone@example.com'] }
        }
      end

      it 'raises Cronitor::Error exception' do
        expect { monitor }.to raise_error(
          Cronitor::Error,
          'rules: This field is required.'
        )
      end
    end
  end

  describe '.ping' do
    let(:monitor) { Cronitor.new token: token, opts: monitor_options }
    let(:monitor_options) do
      {
        name: 'My Fancy Monitor',
        notifications: { emails: ['test@example.com'] },
        rules: [{
          rule_type: 'not_completed_in',
          duration: 5,
          time_unit: 'seconds'
        }],
        note: 'A human-friendly description of this monitor'
      }
    end

    %w[run complete fail].each do |ping_type|
      context 'with a valid monitor' do
        describe ping_type do
          it 'notifies Cronitor' do
            expect(monitor.ping(ping_type)).to eq true
          end
          it 'passes the message to Cronitor' do
            monitor.ping(ping_type, 'your message here')
            expect(FakeCronitor.last_request.params).to include(
              'msg' => 'your message here'
            )
          end
        end
      end

      context 'with an invalid monitor' do
        before { monitor.code = 'ijkl' }

        describe ping_type do
          it 'raises Cronitor::Error exception' do
            expect { monitor.ping(ping_type) }.to raise_error(
              Cronitor::Error,
              'Something else has gone awry. HTTP status: 404'
            )
          end
        end
      end
    end
  end
end
