require 'bundler'
require 'paypal_express'

require 'rspec'

RSpec.configure do |config|
  config.color_enabled = true
  config.tty = true
  config.formatter = 'documentation'
end

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end
