require_relative 'browser_helpers'

module Killbill
  module PaypalExpress
    module BaidSpecHelpers

      include ::Killbill::PaypalExpress::BrowserHelpers

      def baid_setup(payment_processor_account_id = nil)
        @call_context = build_call_context

        options = {:payment_processor_account_id => payment_processor_account_id}

        @amount = BigDecimal.new('100')
        @currency = 'USD'

        kb_account_id = SecureRandom.uuid
        external_key, kb_account_id = create_kb_account(kb_account_id, @plugin.kb_apis.proxied_services[:account_user_api])

        @private_plugin = ::Killbill::PaypalExpress::PrivatePaymentPlugin.new

        # Initiate the setup process
        response = create_token(kb_account_id, @call_context.tenant_id, options)
        token = response.token

        login_and_confirm @private_plugin.to_express_checkout_url(response, @call_context.tenant_id)

        # Complete the setup process
        @properties = []
        @properties << build_property('token', token)
        @pm = create_payment_method(::Killbill::PaypalExpress::PaypalExpressPaymentMethod, kb_account_id, @call_context.tenant_id, @properties)

        verify_payment_method kb_account_id
      end

      private

      def create_token(kb_account_id, kb_tenant_id, options)
        response = @private_plugin.initiate_express_checkout(kb_account_id, kb_tenant_id, @amount, @currency, true, options)
        expect(response.success).to be_truthy
        response
      end

      def verify_payment_method(kb_account_id)
        # Verify our table directly. Note that @pm.token is the baid
        payment_methods = ::Killbill::PaypalExpress::PaypalExpressPaymentMethod.from_kb_account_id_and_token(@pm.token, kb_account_id, @call_context.tenant_id)
        expect(payment_methods.size).to be == 1
        payment_method = payment_methods.first
        expect(payment_method).not_to be_nil
        expect(payment_method.paypal_express_payer_id).not_to be_nil
        expect(payment_method.token).to eq(@pm.token)
        expect(payment_method.kb_payment_method_id).to eq(@pm.kb_payment_method_id)
      end
    end
  end
end
