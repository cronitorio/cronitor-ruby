# Cronitor Ruby Library

![Tests](https://github.com/cronitorio/cronitor-ruby/workflows/Test/badge.svg)
[![Gem Version](https://img.shields.io/gem/v/cronitor?color=brightgreen)](https://rubygems.org/gems/cronitor)


[Cronitor](https://cronitor.io/) provides dead simple monitoring for cron jobs, daemons, queue workers, websites, APIs, and anything else that can send or receive an HTTP request. The Cronitor Ruby library provides convenient access to the Cronitor API from applications written in Ruby. See our [API docs](https://cronitor.io/docs/api) for detailed references on configuring monitors and sending telemetry pings.

In this guide:

- [Installation](#Installation)
- [Monitoring Background Jobs](#monitoring-background-jobs)
- [Sending Telemetry Events](#sending-telemetry-events)
- [Configuring Monitors](#configuring-monitors)
- [Package Configuration & Env Vars](#package-configuration)
- [Contributing](#contributing)

## Installation

```
gem install cronitor
```

## Monitoring Background Jobs

The `Cronitor#job` helper will send telemetry events before calling your block and after it exits. If your block raises an exception a `fail` event will be sent (and the exception re-raised).

```ruby
require 'cronitor'
Cronitor.api_key = 'api_key_123'

Cronitor.job 'important-job' do
    ImportantJob.new(Date.today).run()
end
```

### Integrating with Sidekiq
Cronitor provides a [separate library](https://github.com/cronitorio/cronitor-sidekiq) built with this SDK to make Sidekiq integration even easier.


## Sending Telemetry Events

If you want more control over when/how [telemetry pings](https://cronitor.io/docs/telemetry-api) are sent,
you can instantiate a monitor and call `#ping`.

```ruby
require 'cronitor'
Cronitor.api_key = 'api_key_123'

monitor = Cronitor::Monitor.new('heartbeat-monitor')

monitor.ping # a basic heartbeat event

# optional params can be passed as kwargs
# complete list - https://cronitor.io/docs/telemetry-api#parameters

monitor.ping(state: 'run', env: 'staging') # a job/process has started in a staging environment

# a job/process has completed - include metrics for cronitor to record
monitor.ping(state: 'complete', metrics: {count: 1000, error_count: 17})
```

## Configuring Monitors

### YAML Configuration File

You can configure all of your monitors using a single YAML file. This can be version controlled and synced to Cronitor as part of
a deployment or build process. For details on all of the attributes that can be set, see the [Monitor API](https://cronitor.io/docs/monitor-api) documentation.

```ruby
require 'cronitor'
Cronitor.api_key = 'api_key_123'

# read config file.
Cronitor.read_config('./cronitor.yaml')

# sync config file's monitors to Cronitor.
Cronitor.apply_config

# send config file's monitors to Cronitor to validate correctness.
# monitors will not be saved.
Cronitor.validate_config

# generate a new config file from the Cronitor API.
Cronitor.generate_config
```

The `cronitor.yaml` file includes three top level keys `jobs`, `checks`, `heartbeats`. You can configure monitors under each key by defining [monitors](https://cronitor.io/docs/monitor-api#attributes).

```yaml
jobs:
    nightly-database-backup:
        schedule: 0 0 * * *
        notify:
            - devops-alert-pagerduty
        assertions:
            - metric.duration < 5 minutes

    send-welcome-email:
        schedule: every 10 minutes
        assertions:
            - metric.count > 0
            - metric.duration < 30 seconds

check:
    cronitor-homepage:
        request:
            url: https://cronitor.io
            regions:
                - us-east-1
                - eu-central-1
                - ap-northeast-1
        assertions:
            - response.code = 200
            - response.time < 2s

    cronitor-telemetry-api:
        request:
            url: https://cronitor.link/ping
        assertions:
            - response.body contains ok
            - response.time < .25s

heartbeats:
    production-deploy:
        notify:
            alerts: ['deploys-slack']
            events: true # send alert when the event occurs

```
#### Async Uploads
If you are working with large YAML files (300+ monitors), you may hit timeouts when trying to sync monitors in a single http request. This workload to be processed asynchronously by adding the key `async: true` to the config file. The request will immediately return a `batch_key`. If a `webhook_url` parameter is included, Cronitor will POST to that URL with the results of the background processing and will include the `batch_key` matching the one returned in the initial response.

### Using `Cronitor::Monitor.put`

You can also create and update monitors by calling `Cronitor::Monitor.put`. This method can handle multiple monitors at once and supports various configurations and options.


#### Usage
```ruby
require 'cronitor'

# Define monitors as an array of hashes
monitors = [
  {
    type: 'job',
    key: 'send-customer-invoices',
    schedule: '0 0 * * *',
    assertions: ['metric.duration < 5 min'],
    notify: ['devops-alerts-slack']
  },
  {
    type: 'check',
    key: 'Cronitor Homepage',
    request: { url: 'https://cronitor.io' },
    schedule: 'every 60 seconds',
    assertions: [
      'response.code = 200',
      'response.time < 600ms'
    ]
  }
]

# Options hash with monitors array
options = {
  monitors: monitors,
  format: 'json', # Optional, can be 'json' or 'yaml'
  rollback: false, # Optional, default is false
  timeout: 10 # Optional, specify request timeout in seconds
}

# Create or update monitors
Cronitor::Monitor.put(options)
```

#### Parameters
- `monitors`: An array of monitor configuration hashes.
- `options`: A hash containing:
  - `:monitors`: An array of monitor hashes (required).
  - `:format`: String, format of the request ('json' or 'yaml'). Default is 'json'.
  - `:rollback`: Boolean, indicates whether to rollback on failure. Default is `false`.
  - `:timeout`: Integer, request timeout in seconds. Falls back to `Cronitor.timeout` if not specified.

#### Return Value
Depending on the `:format` option, this method returns:
- For JSON: An array of `Cronitor::Monitor` instances or a single instance if only one monitor is provided.
- For YAML: The parsed response body.

#### Error Handling
- `ValidationError`: Raised when the API returns a 400 status code, indicating invalid monitor configurations.
- `Error`: Raised for other non-successful responses, indicating issues with connecting to the Cronitor API.

### Pause, Reset, Delete

```ruby
require 'cronitor'

monitor = Cronitor::Monitor.new('heartbeat-monitor')

monitor.pause(24) # pause alerting for 24 hours
monitor.unpause # alias for .pause(0)
monitor.ok # manually reset to a passing state alias for monitor.ping({state: ok})
monitor.delete # destroy the monitor
```

## Package Configuration

The package needs to be configured with your account's `API key`, which is available on the [account settings](https://cronitor.io/settings) page. You can also optionally specify an `api_version` and an `environment`. If not provided, your account default is used. These can also be supplied using the environment variables `CRONITOR_API_KEY`, `CRONITOR_API_VERSION`, `CRONITOR_ENVIRONMENT`.

```ruby
require 'cronitor'

# your api keys can found here - https://cronitor.io/settings
Cronitor.api_key = 'apiKey123'
Cronitor.api_version = '2020-10-01'
Cronitor.environment = 'cluster_1_prod'

Cronitor.timeout = 20 # defaults to 10 can also be set with ENV['CRONITOR_TIMEOUT']
Cronitor.logger = nil # defaults to Logger.new($stdout)
# faster timeout for potentially more time sensitive call
Cronitor.ping_timeout = 10 # defaults to 5 can also be set with ENV['CRONITOR_PING_TIMEOUT']
```

## Contributing

Pull requests and features are happily considered! By participating in this project you agree to abide by the [Code of Conduct](http://contributor-covenant.org/version/2/0).

### To contribute

Fork, then clone the repo:

    git clone git@github.com:your-username/cronitor-ruby.git


Set up your machine:

    bin/setup


Make sure the tests pass:

    rake spec


Make your change. You can experiment using:

    bin/console


Add tests for your change. Make the tests pass:

    rake spec

Push to your fork and [submit a pull request]( https://github.com/cronitorio/cronitor-ruby/compare/)


## Release a new version

The bump gem makes this easy:

1. `rake bump:(major|minor|patch|pre)`
2. `rake release`
