module Killbill #:nodoc:
  module PaypalExpress #:nodoc:
    class PrivatePaymentPlugin < ::Killbill::Plugin::ActiveMerchant::PrivatePaymentPlugin
      def initialize(session = {})
        super(:paypal_express,
              ::Killbill::PaypalExpress::PaypalExpressPaymentMethod,
              ::Killbill::PaypalExpress::PaypalExpressTransaction,
              ::Killbill::PaypalExpress::PaypalExpressResponse,
              session)
      end

      # See https://cms.paypal.com/uk/cgi-bin/?cmd=_render-content&content_ID=developer/e_howto_api_ECReferenceTxns
      def initiate_express_checkout(kb_account_id, kb_tenant_id, amount_in_cents=0, currency='USD', with_baid=true, options = {})
        payment_processor_account_id = (options[:payment_processor_account_id] || :default)

        options[:currency]          ||= currency

        # Required arguments
        options[:return_url]        ||= 'http://www.example.com/success'
        options[:cancel_return_url] ||= 'http://www.example.com/sad_panda'

        if with_baid
          options[:billing_agreement]               ||= {}
          options[:billing_agreement][:type]        ||= 'MerchantInitiatedBilling'
          options[:billing_agreement][:description] ||= 'Kill Bill billing agreement'
        end

        # Go to Paypal (SetExpressCheckout call)
        payment_processor_account_id              = options[:payment_processor_account_id] || :default
        paypal_express_response                   = gateway(payment_processor_account_id, kb_tenant_id).setup_authorization(amount_in_cents, options)
        response, transaction                     = save_response_and_transaction(paypal_express_response, :initiate_express_checkout, kb_account_id, kb_tenant_id, payment_processor_account_id)

        response
      end

      def to_express_checkout_url(response, kb_tenant_id = nil, options = {})
        payment_processor_account_id = options[:payment_processor_account_id] || :default
        gateway                      = gateway(payment_processor_account_id, kb_tenant_id)
        gateway.redirect_url_for(response.token)
      end
    end
  end
end
