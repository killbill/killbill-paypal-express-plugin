module Killbill #:nodoc:
  module PaypalExpress #:nodoc:
    class PrivatePaymentPlugin < ::Killbill::Plugin::ActiveMerchant::PrivatePaymentPlugin

      ONE_HOUR_AGO = 3600
      STATUS = {:CAPTURE   => {:success_status => 'Completed', :type => 'Payment'},
                :AUTHORIZE => {:success_status => 'Pending',   :type => 'Authorization'},
                :REFUND    => {:success_status => 'Completed', :type => 'Refund'}}

      def initialize(session = {})
        super(:paypal_express,
              ::Killbill::PaypalExpress::PaypalExpressPaymentMethod,
              ::Killbill::PaypalExpress::PaypalExpressTransaction,
              ::Killbill::PaypalExpress::PaypalExpressResponse,
              session)
      end

      # See https://cms.paypal.com/uk/cgi-bin/?cmd=_render-content&content_ID=developer/e_howto_api_ECReferenceTxns
      def initiate_express_checkout(kb_account_id, kb_tenant_id, amount_in_cents=0, currency='USD', with_baid=true, options = {})
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
        payment_processor_account_id = options[:payment_processor_account_id] || :default
        paypal_express_response      = gateway(payment_processor_account_id, kb_tenant_id).setup_authorization(amount_in_cents, options)
        response, transaction        = save_response_and_transaction(paypal_express_response, :initiate_express_checkout, kb_account_id, kb_tenant_id, payment_processor_account_id)

        response
      end

      def to_express_checkout_url(response, kb_tenant_id = nil, options = {})
        payment_processor_account_id = options[:payment_processor_account_id] || :default
        gateway                      = gateway(payment_processor_account_id, kb_tenant_id)
        review                       = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(options, :review)
        gateway.redirect_url_for(response.token, :review => review)
      end

      def get_external_keys_for_accounts(kb_account_ids, kb_tenant_id)
        context = kb_apis.create_context(kb_tenant_id)
        kb_account_ids.map {|id| kb_apis.account_user_api.get_account_by_id(id, context).external_key }
      end

      def fix_unknown_transaction(plugin_response, trx_plugin_info, gateway)
        status, transaction_id, type, amount, currency = search_transaction(trx_plugin_info.created_date - ONE_HOUR_AGO,
                                                                            gateway,
                                                                            trx_plugin_info.kb_transaction_payment_id)
        return false if status.blank? || transaction_id.blank? || type.blank?

        if type == STATUS[trx_plugin_info.transaction_type][:type] &&
           status == STATUS[trx_plugin_info.transaction_type][:success_status]
          plugin_response.transition_to_success transaction_id, amount, currency
          logger.info("Fixed UNDEFINED kb_transaction_id='#{trx_plugin_info.kb_transaction_payment_id}' to PROCESSED")
          return true
        end

        false
      end

      def search_transaction(start_time, gateway, kb_payment_transaction_id)
        options = {:start_date => start_time, :invoice_id => kb_payment_transaction_id}
        response = gateway.transaction_search options
        [response.params['status'], response.authorization, response.params['type'], response.params['gross_amount'], response.params['gross_amount_currency_id']]
      end
    end
  end
end
