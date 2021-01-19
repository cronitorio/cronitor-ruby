# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cronitor/version'

Gem::Specification.new do |spec|
  spec.name        = 'cronitor'
  spec.version     = Cronitor::VERSION
  spec.authors     = ['Jeff Byrnes', 'August Flanagan']
  spec.email       = ['thejeffbyrnes@gmail.com', 'august@cronitor.io']

  spec.summary     = 'An interface for the Cronitor API'
  spec.homepage    = 'https://github.com/cronitorio/cronitor-ruby'

  spec.required_ruby_version = '~> 2.4'

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'httparty'

  spec.add_development_dependency 'bump', '~> 0.1'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'pry', '~> 0.10'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec', '~> 3.3'
  spec.add_development_dependency 'rubocop', '~> 1.8'
  spec.add_development_dependency 'rubocop-rake', '~> 0.5.1'
  spec.add_development_dependency 'rubocop-rspec', '~> 2.1'
  spec.add_development_dependency 'sinatra', '~> 2.0'
  spec.add_development_dependency 'webmock', '~> 3.1'
end
