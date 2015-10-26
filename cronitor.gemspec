lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cronitor/version'

Gem::Specification.new do |spec|
  spec.name        = 'cronitor'
  spec.version     = Cronitor::VERSION
  spec.authors     = ['Jeff Byrnes']
  spec.email       = ['thejeffbyrnes@gmail.com']

  spec.summary     = 'An interface for the Cronitor API'
  spec.homepage    = 'https://github.com/evertrue/cronitor'

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'unirest', '~> 1.1'
  spec.add_dependency 'hashie', '~> 3.4'

  spec.add_development_dependency 'bundler', '~> 1.10'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.3'
  spec.add_development_dependency 'pry', '~> 0.10'
  spec.add_development_dependency 'webmock', '~> 1.21'
  spec.add_development_dependency 'sinatra', '~> 1.4'
  spec.add_development_dependency 'bump', '~> 0.1'
end
