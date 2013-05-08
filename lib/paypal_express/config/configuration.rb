require 'logger'

module Killbill::PaypalExpress
  mattr_reader :logger
  mattr_reader :config
  mattr_reader :gateway
  mattr_reader :paypal_sandbox_url
  mattr_reader :paypal_production_url
  mattr_reader :initialized
  mattr_reader :test

  def self.initialize!(logger=Logger.new(STDOUT), conf_dir=File.expand_path('../../../', File.dirname(__FILE__)))
    @@logger = logger

    config_file = "#{conf_dir}/paypal_express.yml"
    @@config = Properties.new(config_file)
    @@config.parse!

    @@paypal_sandbox_url = @@config[:paypal][:sandbox_url] || 'https://www.sandbox.paypal.com/cgi-bin/webscr'
    @@paypal_production_url = @@config[:paypal][:production_url] || 'https://www.paypal.com/cgi-bin/webscr'
    @@test = @@config[:paypal][:test]

    @@gateway = Killbill::PaypalExpress::Gateway.instance
    @@gateway.configure(@@config[:paypal])

    if defined?(JRUBY_VERSION)
      # See https://github.com/jruby/activerecord-jdbc-adapter/issues/302
      require 'jdbc/mysql'
      Jdbc::MySQL.load_driver(:require) if Jdbc::MySQL.respond_to?(:load_driver)
    end

    ActiveRecord::Base.establish_connection(@@config[:database])

    @@initialized = true
  end
end