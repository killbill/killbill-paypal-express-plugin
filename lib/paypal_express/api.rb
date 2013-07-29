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

    def process_payment(kb_account_id, kb_payment_id, kb_payment_method_id, amount, currency, call_context = nil, options = {})
      amount_in_cents = (amount * 100).to_i

      # If the payment was already made, just return the status
      paypal_express_transaction = PaypalExpressTransaction.from_kb_payment_id(kb_payment_id) rescue nil
      return paypal_express_transaction.paypal_express_response.to_payment_response unless paypal_express_transaction.nil?

      options[:currency] ||= currency.to_s
      options[:payment_type] ||= 'Any'
      options[:invoice_id] ||= kb_payment_id
      options[:description] ||= "Kill Bill payment for #{kb_payment_id}"
      options[:ip] ||= @ip

      if options[:reference_id].blank?
        payment_method = PaypalExpressPaymentMethod.from_kb_payment_method_id(kb_payment_method_id)
        options[:reference_id] = payment_method.paypal_express_baid
      end

      # Go to Paypal (DoReferenceTransaction call)
      paypal_response = @gateway.reference_transaction amount_in_cents, options
      response = save_response_and_transaction paypal_response, :charge, kb_payment_id, amount_in_cents

      response.to_payment_response
    end

    def get_payment_info(kb_account_id, kb_payment_id, tenant_context = nil, options = {})
      paypal_express_transaction = PaypalExpressTransaction.from_kb_payment_id(kb_payment_id)

      begin
        transaction_id = paypal_express_transaction.paypal_express_txn_id
        response = @gateway.transaction_details transaction_id
        PaypalExpressResponse.from_response(:transaction_details, kb_payment_id, response).to_payment_response
      rescue => e
        @logger.warn("Exception while retrieving Paypal Express transaction detail for payment #{kb_payment_id}, defaulting to cached response: #{e}")
        paypal_express_transaction.paypal_express_response.to_payment_response
      end
    end

    def process_refund(kb_account_id, kb_payment_id, amount, currency, call_context = nil, options = {})
      amount_in_cents = (amount * 100).to_i

      paypal_express_transaction = PaypalExpressTransaction.find_candidate_transaction_for_refund(kb_payment_id, amount_in_cents)

      options[:currency] ||= currency.to_s
      options[:refund_type] ||= paypal_express_transaction.amount_in_cents != amount_in_cents ? 'Partial' : 'Full'

      identification = paypal_express_transaction.paypal_express_txn_id

      # Go to Paypal
      paypal_response = @gateway.refund amount_in_cents, identification, options
      response = save_response_and_transaction paypal_response, :refund, kb_payment_id, amount_in_cents

      response.to_refund_response
    end

    def get_refund_info(kb_account_id, kb_payment_id, tenant_context = nil, options = {})
      paypal_express_transaction = PaypalExpressTransaction.refund_from_kb_payment_id(kb_payment_id)

      begin
        transaction_id = paypal_express_transaction.paypal_express_txn_id
        response = @gateway.transaction_details transaction_id
        PaypalExpressResponse.from_response(:transaction_details, kb_payment_id, response).to_refund_response
      rescue => e
        @logger.warn("Exception while retrieving Paypal Express transaction detail for payment #{kb_payment_id}, defaulting to cached response: #{e}")
        paypal_express_transaction.paypal_express_response.to_refund_response
      end
    end

    def add_payment_method(kb_account_id, kb_payment_method_id, payment_method_props, set_default = false, call_context = nil, options = {})
      token = (payment_method_props.properties.find { |kv| kv.key == 'token' }).value
      return false if token.nil?

      # The payment method should have been created during the setup step (see private api)
      payment_method = PaypalExpressPaymentMethod.from_kb_account_id_and_token(kb_account_id, token)

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

        payment_method.kb_payment_method_id = kb_payment_method_id
        payment_method.paypal_express_payer_id = payer_id
        payment_method.paypal_express_baid = response.billing_agreement_id
        payment_method.save!

        logger.info "Created BAID #{payment_method.paypal_express_baid} for payment method #{kb_payment_method_id} (account #{kb_account_id})"
        true
      else
        logger.warn "Unable to retrieve Payer id details for token #{token} (account #{kb_account_id})"
        false
      end
    end

    def delete_payment_method(kb_account_id, kb_payment_method_id, call_context = nil, options = {})
      PaypalExpressPaymentMethod.mark_as_deleted! kb_payment_method_id
    end

    def get_payment_method_detail(kb_account_id, kb_payment_method_id, tenant_context = nil, options = {})
      PaypalExpressPaymentMethod.from_kb_payment_method_id(kb_payment_method_id).to_payment_method_response
    end

    def set_default_payment_method(kb_account_id, kb_payment_method_id, call_context = nil, options = {})
      # No-op
    end

    def get_payment_methods(kb_account_id, refresh_from_gateway, call_context = nil, options = {})
      PaypalExpressPaymentMethod.from_kb_account_id(kb_account_id).collect { |pm| pm.to_payment_method_info_response }
    end

    def reset_payment_methods(kb_account_id, payment_methods)
      return if payment_methods.nil?

      paypal_pms = PaypalExpressPaymentMethod.from_kb_account_id(kb_account_id)

      payment_methods.delete_if do |payment_method_info_plugin|
        should_be_deleted = false
        paypal_pms.each do |paypal_pm|
          # Do paypal_pm and payment_method_info_plugin represent the same PayPal payment method?
          if paypal_pm.external_payment_method_id == payment_method_info_plugin.external_payment_method_id
            # Do we already have a kb_payment_method_id?
            if paypal_pm.kb_payment_method_id == payment_method_info_plugin.payment_method_id
              should_be_deleted = true
              break
            elsif paypal_pm.kb_payment_method_id.nil?
              # We didn't have the kb_payment_method_id - update it
              paypal_pm.kb_payment_method_id = payment_method_info_plugin.payment_method_id
              should_be_deleted = paypal_pm.save
              break
              # Otherwise the same BAID points to 2 different kb_payment_method_id. This should never happen,
              # but we cowardly will insert a second row below
            end
          end
        end

        should_be_deleted
      end

      # The remaining elements in payment_methods are not in our table (this should never happen?!)
      payment_methods.each do |payment_method_info_plugin|
        PaypalExpressPaymentMethod.create :kb_account_id => payment_method_info_plugin.account_id,
                                          :kb_payment_method_id => payment_method_info_plugin.payment_method_id,
                                          :paypal_express_baid => payment_method_info_plugin.external_payment_method_id,
                                          :paypal_express_token => 'unknown (created by reset)'
      end
    end

    def search_payment_methods(search_key, call_context = nil, options = {})
      PaypalExpressPaymentMethod.search(search_key).map(&:to_payment_method_response)
    end

    private

    def save_response_and_transaction(paypal_express_response, api_call, kb_payment_id=nil, amount_in_cents=0)
      @logger.warn "Unsuccessful #{api_call}: #{paypal_express_response.message}" unless paypal_express_response.success?

      # Save the response to our logs
      response = PaypalExpressResponse.from_response(api_call, kb_payment_id, paypal_express_response)
      response.save!

      if response.success and !kb_payment_id.blank? and !response.authorization.blank?
        # Record the transaction
        transaction = response.create_paypal_express_transaction!(:amount_in_cents => amount_in_cents, :api_call => api_call, :kb_payment_id => kb_payment_id, :paypal_express_txn_id => response.authorization)
        @logger.debug "Recorded transaction: #{transaction.inspect}"
      end
      response
    end
  end
end
