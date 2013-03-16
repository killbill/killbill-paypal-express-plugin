module Killbill::PaypalExpress
  class PrivatePaymentPlugin
    include Singleton

    def initiate_express_checkout(amount_in_cents, options = {})
      # TODO
      # options[:currency] ||=

      # Required arguments
      options[:return_url] ||= 'http://www.example.com/success'
      options[:cancel_return_url] ||= 'http://www.example.com/sad_panda'

      options[:billing_agreement] ||= {}
      options[:billing_agreement][:type] ||= "RecurringPayments"
      options[:billing_agreement][:description] ||= "Kill Bill agreement"

      # Go to Paypal
      paypal_express_response = gateway.setup_authorization amount_in_cents, options
      response = save_response paypal_express_response, :initiate_express_checkout, amount_in_cents

      response
    end

    private

    def gateway
      # The gateway should have been configured when the plugin started
      Killbill::PaypalExpress::Gateway.instance
    end

    def save_response(paypal_express_response, api_call, amount_in_cents=0)
      # Save the response to our logs
      response = PaypalExpressResponse.from_response(api_call, nil, paypal_express_response)
      response.save!
      response
    end
  end
end