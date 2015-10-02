# Cronitor

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

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

1. Fork it ( https://github.com/evertrue/cronitor/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
