require 'activemerchant'
require 'singleton'

module PaypalExpress
  class Gateway
    include Singleton

    def configure(config)
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
