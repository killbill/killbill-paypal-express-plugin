module Killbill::PaypalExpress
  class PaymentPlugin < Killbill::Plugin::Payment
    def start_plugin
      Killbill::PaypalExpress.initialize! @logger, @conf_dir
      @gateway = Killbill::PaypalExpress.gateway

      @ip = Utils.ip

      super

      @logger.info "Killbill::PaypalExpress::PaymentPlugin started"
    end

    # return DB connections to the Pool if required
    def after_request
      ActiveRecord::Base.connection.close
    end

    def process_payment(kb_account_id, kb_payment_id, kb_payment_method_id, amount_in_cents, currency, call_context, options = {})
      # If the payment was already made, just return the status
      paypal_express_transaction = PaypalExpressTransaction.from_kb_payment_id(kb_payment_id.to_s) rescue nil
      return paypal_express_transaction.paypal_express_response.to_payment_response unless paypal_express_transaction.nil?

      options[:currency] ||= currency.respond_to?(:enum) ? currency.enum : currency.to_s
      options[:payment_type] ||= 'Any'
      options[:invoice_id] ||= kb_payment_id.to_s
      options[:description] ||= "Kill Bill payment for #{kb_payment_id}"
      options[:ip] ||= @ip

      if options[:reference_id].blank?
        payment_method = PaypalExpressPaymentMethod.from_kb_payment_method_id(kb_payment_method_id.to_s)
        options[:reference_id] = payment_method.paypal_express_baid
      end

      # Go to Paypal (DoReferenceTransaction call)
      paypal_response = @gateway.reference_transaction amount_in_cents, options
      response = save_response_and_transaction paypal_response, :charge, kb_payment_id, amount_in_cents

      response.to_payment_response
    end

    def get_payment_info(kb_account_id, kb_payment_id, tenant_context, options = {})
      paypal_express_transaction = PaypalExpressTransaction.from_kb_payment_id(kb_payment_id.to_s)

      begin
        transaction_id = paypal_express_transaction.paypal_express_txn_id
        response = @gateway.transaction_details transaction_id
        PaypalExpressResponse.from_response(:transaction_details, kb_payment_id.to_s, response).to_payment_response
      rescue => e
        @logger.warn("Exception while retrieving Paypal Express transaction detail for payment #{kb_payment_id.to_s}, defaulting to cached response: #{e}")
        paypal_express_transaction.paypal_express_response.to_payment_response
      end
    end

    def process_refund(kb_account_id, kb_payment_id, amount_in_cents, currency, call_context, options = {})
      paypal_express_transaction = PaypalExpressTransaction.find_candidate_transaction_for_refund(kb_payment_id.to_s, amount_in_cents)

      options[:currency] ||= currency.respond_to?(:enum) ? currency.enum : currency.to_s
      options[:refund_type] ||= paypal_express_transaction.amount_in_cents != amount_in_cents ? 'Partial' : 'Full'

      identification = paypal_express_transaction.paypal_express_txn_id

      # Go to Paypal
      paypal_response = @gateway.refund amount_in_cents, identification, options
      response = save_response_and_transaction paypal_response, :refund, kb_payment_id, amount_in_cents

      response.to_refund_response
    end

    def get_refund_info(kb_account_id, kb_payment_id, tenant_context, options = {})
      paypal_express_transaction = PaypalExpressTransaction.refund_from_kb_payment_id(kb_payment_id.to_s)

      begin
        transaction_id = paypal_express_transaction.paypal_express_txn_id
        response = @gateway.transaction_details transaction_id
        PaypalExpressResponse.from_response(:transaction_details, kb_payment_id.to_s, response).to_refund_response
      rescue => e
        @logger.warn("Exception while retrieving Paypal Express transaction detail for payment #{kb_payment_id.to_s}, defaulting to cached response: #{e}")
        paypal_express_transaction.paypal_express_response.to_refund_response
      end
    end

    def add_payment_method(kb_account_id, kb_payment_method_id, payment_method_props, set_default, call_context, options = {})
      token = (payment_method_props.properties.find { |kv| kv.key == 'token' }).value
      return false if token.nil?

      # The payment method should have been created during the setup step (see private api)
      payment_method = PaypalExpressPaymentMethod.from_kb_account_id_and_token(kb_account_id.to_s, token)

      # Go to Paypal to get the Payer id (GetExpressCheckoutDetails call)
      paypal_express_details_response = @gateway.details_for token
      response = save_response_and_transaction paypal_express_details_response, :details_for
      return false unless response.success?

      payer_id = response.payer_id
      unless payer_id.nil?
        # Go to Paypal to create the BAID for recurring payments (CreateBillingAgreement call)
        paypal_express_baid_response = @gateway.store token
        response = save_response_and_transaction paypal_express_baid_response, :create_billing_agreement
        return false unless response.success?

        payment_method.kb_payment_method_id = kb_payment_method_id.to_s
        payment_method.paypal_express_payer_id = payer_id
        payment_method.paypal_express_baid = response.billing_agreement_id
        payment_method.save!

        logger.info "Created BAID #{payment_method.paypal_express_baid} for payment method #{kb_payment_method_id.to_s} (account #{kb_account_id.to_s})"
        true
      else
        logger.warn "Unable to retrieve Payer id details for token #{token} (account #{kb_account_id.to_s})"
        false
      end
    end

    def delete_payment_method(kb_account_id, kb_payment_method_id, call_context, options = {})
      PaypalExpressPaymentMethod.mark_as_deleted! kb_payment_method_id.to_s
    end

    def get_payment_method_detail(kb_account_id, kb_payment_method_id, tenant_context, options = {})
      PaypalExpressPaymentMethod.from_kb_payment_method_id(kb_payment_method_id.to_s).to_payment_method_response
    end

    def set_default_payment_method(kb_account_id, kb_payment_method_id, call_context, options = {})
      # No-op
    end

    def get_payment_methods(kb_account_id, refresh_from_gateway, call_context, options = {})
      PaypalExpressPaymentMethod.from_kb_account_id(kb_account_id.to_s).collect { |pm| pm.to_payment_method_response }
    end

    def reset_payment_methods(kb_account_id, payment_methods)
      # No-op
    end

    private

    def save_response_and_transaction(paypal_express_response, api_call, kb_payment_id=nil, amount_in_cents=0)
      @logger.warn "Unsuccessful #{api_call}: #{paypal_express_response.message}" unless paypal_express_response.success?

      # Save the response to our logs
      response = PaypalExpressResponse.from_response(api_call, kb_payment_id.to_s, paypal_express_response)
      response.save!

      if response.success and !kb_payment_id.blank? and !response.authorization.blank?
        # Record the transaction
        transaction = response.create_paypal_express_transaction!(:amount_in_cents => amount_in_cents, :api_call => api_call, :kb_payment_id => kb_payment_id.to_s, :paypal_express_txn_id => response.authorization)
        @logger.debug "Recorded transaction: #{transaction.inspect}"
      end
      response
    end
  end
end
