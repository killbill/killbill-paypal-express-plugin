module Killbill #:nodoc:
  module PaypalExpress #:nodoc:
    class PaypalExpressPaymentMethod < ::Killbill::Plugin::ActiveMerchant::ActiveRecord::PaymentMethod

      self.table_name = 'paypal_express_payment_methods'

      def self.from_response(kb_account_id, kb_payment_method_id, kb_tenant_id, cc_or_token, response, options, extra_params = {}, model = ::Killbill::PaypalExpress::PaypalExpressPaymentMethod)
        super(kb_account_id,
              kb_payment_method_id,
              kb_tenant_id,
              cc_or_token,
              response,
              options,
              {
                  :paypal_express_token    => options[:paypal_express_token],
                  :paypal_express_payer_id => options[:paypal_express_payer_id],
              }.merge!(extra_params),
              model)
      end

      def to_payment_method_plugin
        pm_plugin = super

        pm_plugin.properties << create_plugin_property('paypalExpressToken', paypal_express_token)
        pm_plugin.properties << create_plugin_property('payerId', paypal_express_payer_id)
        pm_plugin.properties << create_plugin_property('baid', token)

        pm_plugin
      end
    end
  end
end
