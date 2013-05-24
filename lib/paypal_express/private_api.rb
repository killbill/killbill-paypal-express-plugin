module Killbill::PaypalExpress
  class PrivatePaymentPlugin
    include Singleton

    # See https://cms.paypal.com/uk/cgi-bin/?cmd=_render-content&content_ID=developer/e_howto_api_ECReferenceTxns
    def initiate_express_checkout(kb_account_id, amount_in_cents=0, currency='USD', options = {})
      options[:currency] ||= currency

      # Required arguments
      options[:return_url] ||= 'http://www.example.com/success'
      options[:cancel_return_url] ||= 'http://www.example.com/sad_panda'

      options[:billing_agreement] ||= {}
      options[:billing_agreement][:type] ||= "MerchantInitiatedBilling"
      options[:billing_agreement][:description] ||= "Kill Bill billing agreement"

      # Go to Paypal (SetExpressCheckout call)
      paypal_express_response = gateway.setup_authorization amount_in_cents, options
      response = save_response paypal_express_response, :initiate_express_checkout

      if response.success?
        # Create the payment method (not associated to a Killbill payment method yet)
        Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => kb_account_id,
                                                                   :kb_payment_method_id => nil,
                                                                   :paypal_express_payer_id => nil,
                                                                   :paypal_express_token => response.token
      end

      response
    end

    private

    def save_response(paypal_express_response, api_call)
      logger.warn "Unsuccessful #{api_call}: #{paypal_express_response.message}" unless paypal_express_response.success?

      # Save the response to our logs
      response = PaypalExpressResponse.from_response(api_call, nil, paypal_express_response)
      response.save!
      response
    end

    def gateway
      # The gateway should have been configured when the plugin started
      Killbill::PaypalExpress::Gateway.instance
    end

    def logger
      # The logger should have been configured when the plugin started
      Killbill::PaypalExpress.logger
    end
  end
end
