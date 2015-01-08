# encoding: UTF-8

source 'https://rubygems.org'

%w(
  bosh_cli_plugin_micro
  bosh-registry
  bosh_vsphere_cpi
).each do |gem_name|
  gem gem_name, path: gem_name
end

gem 'rake', '~>10.0'

group :production do
  # this was pulled from bosh_aws_registry's Gemfile.  Why does it exist?
  # also bosh_openstack_registry, director
  gem 'pg'
  gem 'mysql2'
end

group :bat do
  gem 'httpclient'
  gem 'json'
  gem 'minitar'
  gem 'net-ssh'
end

group :development, :test do
  gem 'rspec', '~> 3.0'
  gem 'rspec-its'

  gem 'rubocop', require: false
  gem 'parallel_tests'
  gem 'rack-test'
  gem 'webmock'
  gem 'fakefs', git: 'https://github.com/pivotal-cf-experimental/fakefs.git', ref: 'ebde3d6c'
  gem 'simplecov', '~> 0.9.0'
  gem 'codeclimate-test-reporter', require: false
  gem 'vcr'

  # Explicitly do not require serverspec dependency
  # so that it could be monkey patched in a deterministic way
  # in `bosh-stemcell/spec/support/serverspec.rb`
  gem 'specinfra', require: nil

  # for director
  gem 'machinist', '~>1.0'

  # for root level specs
  gem 'rest-client'
  gem 'redis'
  gem 'nats'
  gem 'rugged'

  gem 'sqlite3'
  gem 'timecop'
  gem 'jenkins_api_client'
end
