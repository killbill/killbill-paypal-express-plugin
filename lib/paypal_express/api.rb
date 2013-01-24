require 'active_merchant'
require 'logger'
require 'killbill'
require 'paypal_express/config'

module PaypalExpress
  class PaymentPlugin < Killbill::Plugin::Payment
    attr_writer :config_file

    def start_plugin
      @logger = Logger.new(STDOUT)

      config = Config.new(@config_file)
      config.parse!

      @gateway = ActiveMerchant::Billing::PaypalExpressGateway.new({
                                                                     :signature => config[:paypal][:signature],
                                                                     :login => config[:paypal][:login],
                                                                     :password => config[:paypal][:password]
                                                                   })

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
