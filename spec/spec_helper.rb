$: << File.join(File.dirname(__FILE__), "/../../lib")
require 'spec/autorun'
# require 'spec/rails'
require 'red5wrapper'

Spec::Runner.configure do |config|
  config.mock_with :mocha
end
