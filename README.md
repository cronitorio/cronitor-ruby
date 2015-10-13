# Cronitor

[![Travis](https://img.shields.io/travis/evertrue/cronitor.svg)](https://github.com/evertrue/cronitor)
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

### Creating a Monitor

A Cronitor monitor (hereafter referred to only as a monitor for brevity) is created if it does not already exist, and its ID returned.

```ruby
require 'cronitor'

monitor_options = {
    name: 'My Fancy Monitor',
    notifications: {
        emails: [],
        slack: [],
        pagerduty: [],
        phones: [],
        webhooks: []
    },
    rules: [
        {
            rule_type: 'not_run_in',
            duration: 5
            time_unit: 'seconds'
        }
    ],
    note: 'A human-friendly description of this monitor'
}
my_monitor = Cronitor.new token: 'api_token', opts: monitor_options
```

### Pinging a Monitor

Once you’ve created a monitor, you can continue to use the existing instance of the object to ping the monitor that your task status: `run`, `complete`, or `fail`.

```ruby
my_monitor.run
my_monitor.complete
my_monitor.fail 'A short description of the failure'
```

### Pinging a monitor when you have a Cronitor code

You may already have the code for a monitor, in which case, the expense of `Cronitor.new` may seem unnecessary (since it makes an HTTP request to check if a monitor exists, and you already know it does).

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
