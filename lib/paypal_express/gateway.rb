require 'activemerchant'
require 'singleton'

module Killbill::PaypalExpress
  class Gateway
    include Singleton

    def configure(config)
      if config[:log_file]
        ActiveMerchant::Billing::PaypalExpressGateway.wiredump_device = File.open(config[:log_file], 'w')
        ActiveMerchant::Billing::PaypalExpressGateway.wiredump_device.sync = true
      end

      @gateway = ActiveMerchant::Billing::PaypalExpressGateway.new({
                                                                     :signature => config[:signature],
                                                                     :login => config[:login],
                                                                     :password => config[:password]
                                                                   })
    end

    def method_missing(m, *args, &block)
      @gateway.send(m, *args, &block)
    end
  end
end
