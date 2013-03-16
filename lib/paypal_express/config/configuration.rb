module Killbill::PaypalExpress
  mattr_accessor :config
  mattr_accessor :gateway
  mattr_accessor :logger
  mattr_accessor :paypal_sandbox_url
  mattr_accessor :paypal_production_url

  mattr_reader :initialized
  mattr_reader :test

  def self.initialize!(config_file, logger)
    @@logger = logger

    @@config = Properties.new(config_file)
    @@config.parse!

    @@paypal_sandbox_url = @@config[:paypal][:sandbox_url] || 'https://www.sandbox.paypal.com/cgi-bin/webscr'
    @@paypal_production_url = @@config[:paypal][:production_url] || 'https://www.paypal.com/cgi-bin/webscr'
    @@test = @@config[:paypal][:test]

    @@gateway = Killbill::PaypalExpress::Gateway.instance
    @@gateway.configure(@@config[:paypal])

    ActiveRecord::Base.establish_connection(@@config[:database])

    @@initialized = true
  end
end