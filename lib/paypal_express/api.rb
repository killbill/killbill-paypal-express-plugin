require 'killbill'
require 'paypal_express/config'
require 'paypal_express/gateway'

module Killbill::PaypalExpress
  class PaymentPlugin < Killbill::Plugin::Payment
    attr_writer :config_file_name

    def start_plugin
      config = Config.new("#{@root}/#{@config_file_name || 'paypal_express.yml'}")
      config.parse!

      @gateway = Killbill::PaypalExpress::Gateway.instance
      @gateway.configure(config[:paypal])

      super
      @logger.info "Killbill::PaypalExpress::PaymentPlugin started"
    end

    def charge(kb_payment_id, kb_payment_method_id, amount_in_cents, options = {})
    end

    def refund(kb_payment_id, amount_in_cents, options = {})
    end

    def get_payment_info(kb_payment_id, options = {})
    end

    def add_payment_method(kb_account_id, kb_payment_method_id, payment_method_props, set_default, options = {})
    end

    def delete_payment_method(kb_payment_method_id, options = {})
    end

    def get_payment_method_detail(kb_account_id, kb_payment_method_id, options = {})
    end

    def get_payment_methods(kb_account_id, options = {})
    end

    def create_account(killbill_account, options = {})
    end
  end
end
