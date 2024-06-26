# frozen_string_literal: true

require 'pathname'

ROOT_DIR = Pathname.new(File.expand_path('..', __dir__)) unless defined?(ROOT_DIR)

ENV['RACK_ENV'] = 'test'

require 'bundler/setup'

require 'simplecov'

# Configure SimpleCov
SimpleCov.start do
  track_files 'lib/**/*.rb'
  add_filter 'spec'
end

require 'open3'
require 'thor'
require 'fileutils'

require_relative '../lib/facter/resolvers/base_resolver'

unit_tests = ARGV.grep(/spec_integration/).empty?
Dir[ROOT_DIR.join('spec/mocks/*.rb')].sort.each { |file| require file } if unit_tests

require_relative 'custom_facts/puppetlabs_spec/files'

require 'facter'
require 'facter/framework/cli/cli'
require 'facter/framework/cli/cli_launcher'

if unit_tests
  Dir.glob(File.join('./lib/facter/util', '/**/*/', '*.rb')).sort.each(&method(:require))
  Dir.glob(File.join('./lib/facter/facts', '/**/*/', '*.rb')).sort.each(&method(:require))
  Dir.glob(File.join('./lib/facter/resolvers', '/**/*/', '*.rb')).sort.each(&method(:require))
end

default_coverage = 90
SimpleCov.minimum_coverage ENV['COVERAGE'] || default_coverage

def colorize(str, color)
  "#{color}#{str}#{Facter::RESET}"
end

# Configure webmock
require 'webmock/rspec'
WebMock.disable_net_connect!

# Configure test logger
logdest = ENV['FACTER_TEST_LOG'] ? File.new(ENV['FACTER_TEST_LOG'], 'w') : StringIO.new
logger = Logger.new(logdest)

# Configure RSpec
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!
  config.expose_dsl_globally = true

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    # This option should be set when all dependencies are being loaded
    # before a spec run, as is the case in a typical spec helper. It will
    # cause any verifying double instantiation for a class that does not
    # exist to raise, protecting against incorrectly spelt names.
    mocks.verify_doubled_constant_names = true

    # This option forces the same argument and method existence checks that are
    # performed for object_double are also performed on partial doubles.
    # You should set this unless you have a good reason not to.
    # It defaults to off only for backwards compatibility.

    mocks.verify_partial_doubles = true
  end

  config.before(:all) do
    Facter::Log.class_variable_set(:@@logger, logger) # rubocop:disable Style/ClassVars
  end

  config.before do |test|
    m = test.metadata
    logger.info("*** BEGIN TEST #{m[:file_path]}:#{m[:line_number]}")

    LegacyFacter.clear
    Facter.clear_messages
  end

  config.after do
    Facter::OptionStore.reset
    Facter::ConfigReader.clear
    Facter::ConfigFileOptions.clear
  end

  # This will cleanup any files that were created with tmpdir or tmpfile
  config.extend PuppetlabsSpec::Files
  config.after do
    PuppetlabsSpec::Files.cleanup
  end
end
