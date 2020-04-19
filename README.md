# Cronitor

[![Travis](https://img.shields.io/travis/evertrue/cronitor.svg)](https://travis-ci.org/evertrue/cronitor)
[![Gem Version](https://badge.fury.io/rb/cronitor.svg)](https://badge.fury.io/rb/cronitor)

[Cronitor](https://cronitor.io/) is a service for heartbeat-style monitoring of just about anything that can send an HTTP request.

This gem provides a simple abstraction for the creation and pinging of a Cronitor monitor. For a better understanding of the API this gem talks to, please see [How Cronitor Works](https://cronitor.io/help/how-cronitor-works).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'cronitor'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install cronitor

## Usage


### Configure

You need to set Cronitor Token in order to create a monitor

#### Using configure

```ruby
require 'cronitor'

Cronitor.configure do |cronitor|
  cronitor.default_token = 'token' # default token to be re-used by cronitor
end
````

#### Using ENV

```
# .env
CRONITOR_TOKEN = 'token'
```

### Creating a Monitor

A Cronitor monitor (hereafter referred to only as a monitor for brevity) is created if it does not already exist, and its ID returned.

Please see the [Cronitor Monitor API docs](https://cronitor.io/docs/monitor-api) for details of all the possible monitor options.

Example of creating a heartbeat monitor:

```ruby
require 'cronitor'

monitor_options = {
  name: 'My Fancy Monitor',
  type: 'heartbeat', # Optional: the gem defaults to this; the other value, 'healthcheck', is not yet supported by this gem
  notifications: {
    emails: ['test@example.com'],
    slack: [],
    pagerduty: [],
    phones: [],
    webhooks: []
  },
  rules: [
    {
      rule_type: 'run_ping_not_received',
      value: 5,
      time_unit: 'seconds'
    }
  ],
  note: 'A human-friendly description of this monitor'
}

# The token parameter is optional; if omittted, ENV['CRONITOR_TOKEN'] will be used if not configured
my_monitor = Cronitor.new token: 'api_token', opts: monitor_options
```

### Updating an existing monitor

Currently this gem does not support updating or deleting an existing monitor.

### Pinging a Monitor

Once you’ve created a monitor, you can continue to use the existing instance of the object to ping the monitor that your task status: `run`, `complete`, or `fail`.

```ruby
my_monitor.ping 'run'
my_monitor.ping 'complete'
my_monitor.ping 'fail', 'A short description of the failure'
```

### Pinging a monitor when you have a Cronitor code

You may already have the code for a monitor, in which case, the expense of `Cronitor.create` may seem unnecessary (since it makes an HTTP request to check if a monitor exists, and you already know it does).

Cronitor does not require a token for pinging a monitor unless you have enabled Ping API authentication in your account settings. At the moment, this gem does not support Ping API auth.

In that case:

```ruby
my_monitor = Cronitor.new code: 'abcd'
```

The aforementioned ping methods can now be used.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

1. Fork it ( https://github.com/evertrue/cronitor/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Release a new version

The `bump` gem makes this easy:

1. `rake bump:(major|minor|patch|pre)`
2. `rake release`
