require 'killbill'
require 'paypal_express/config'
require 'paypal_express/gateway'

module PaypalExpress
  class PaymentPlugin < Killbill::Plugin::Payment
    def start_plugin
      config = Config.new("#{@root}/paypal_express.yml")
      config.parse!

      @gateway = PaypalExpress::Gateway.instance
      @gateway.configure(config[:paypal])

      super
      @logger.info "PaypalExpress::PaymentPlugin started"
    end

    def charge(killbill_account_id, killbill_payment_id, amount_in_cents, options = {})
    end

    def refund(killbill_account_id, killbill_payment_id, amount_in_cents, options = {})
    end

    def get_payment_info(killbill_payment_id, options = {})
    end

    def add_payment_method(payment_method, options = {})
    end

    def delete_payment_method(external_payment_method_id, options = {})
    end

    def update_payment_method(payment_method, options = {})
    end

    def set_default_payment_method(payment_method, options = {})
    end

    def create_account(killbill_account, options = {})
    end
  end
end
