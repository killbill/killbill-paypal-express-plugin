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
      # Use Money to compute the amount in cents, as it depends on the currency (1 cent of BTC is 1 Satoshi, not 0.01 BTC)
      amount_in_cents = Money.new_with_amount(amount, currency).cents.to_i

      # If the payment was already made, just return the status
      paypal_express_transaction = PaypalExpressTransaction.from_kb_payment_id(kb_payment_id) rescue nil
      return paypal_express_transaction.paypal_express_response.to_payment_response unless paypal_express_transaction.nil?

      # Check for currency conversion
      actual_amount, actual_currency = convert_amount_currency_if_required(amount_in_cents, currency, kb_payment_id)

      options[:currency] ||= actual_currency.to_s
      options[:payment_type] ||= 'Any'
      options[:invoice_id] ||= kb_payment_id
      options[:description] ||= Killbill::PaypalExpress.paypal_payment_description || "Kill Bill payment for #{kb_payment_id}"
      options[:ip] ||= @ip

      if options[:reference_id].blank?
        payment_method = PaypalExpressPaymentMethod.from_kb_payment_method_id(kb_payment_method_id)
        options[:reference_id] = payment_method.paypal_express_baid
      end


      # Go to Paypal (DoReferenceTransaction call)
      paypal_response = @gateway.reference_transaction actual_amount, options
      response = save_response_and_transaction paypal_response, :charge, kb_payment_id, actual_amount, actual_currency

      response.to_payment_response
    end

    def get_payment_info(kb_account_id, kb_payment_id, tenant_context = nil, options = {})
      paypal_express_transaction = PaypalExpressTransaction.from_kb_payment_id(kb_payment_id)

      # We could also re-fetch it via: @gateway.transaction_details(transaction_id)
      # but we would need to reconstruct the payment_info object
      paypal_express_transaction.paypal_express_response.to_payment_response
    end

    def process_refund(kb_account_id, kb_payment_id, amount, currency, call_context = nil, options = {})
      # Use Money to compute the amount in cents, as it depends on the currency (1 cent of BTC is 1 Satoshi, not 0.01 BTC)
      amount_in_cents = Money.new_with_amount(amount, currency).cents.to_i

      # Check for currency conversion
      actual_amount, actual_currency = convert_amount_currency_if_required(amount_in_cents, currency, kb_payment_id)

      paypal_express_transaction = PaypalExpressTransaction.find_candidate_transaction_for_refund(kb_payment_id, actual_amount)

      options[:currency] ||= actual_currency.to_s
      options[:refund_type] ||= paypal_express_transaction.amount_in_cents != actual_amount ? 'Partial' : 'Full'

      identification = paypal_express_transaction.paypal_express_txn_id

      # Go to Paypal
      paypal_response = @gateway.refund actual_amount, identification, options
      response = save_response_and_transaction paypal_response, :refund, kb_payment_id, actual_amount, actual_currency

      response.to_refund_response
    end

    def get_refund_info(kb_account_id, kb_payment_id, tenant_context = nil, options = {})
      paypal_express_transaction = PaypalExpressTransaction.refund_from_kb_payment_id(kb_payment_id)

      # We could also re-fetch it via: @gateway.transaction_details(transaction_id)
      # but we would need to reconstruct the refund_info object
      paypal_express_transaction.paypal_express_response.to_refund_response
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

        if response.billing_agreement_id.blank?
          # If the baid isn't specified (invalid token, maybe expired?), we won't be able to charge that payment method
          # See https://github.com/killbill/killbill-paypal-express-plugin/issues/1
          logger.warn "No BAID returned by the CreateBillingAgreement call for token #{token} (account #{kb_account_id})"
          return false
        end

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

    def search_payments(search_key, offset = 0, limit = 100, call_context = nil, options = {})
      PaypalExpressResponse.search(search_key, offset, limit, :payment)
    end

    def search_payment_methods(search_key, offset = 0, limit = 100, call_context = nil, options = {})
      PaypalExpressPaymentMethod.search(search_key, offset, limit)
    end

    private

    def convert_amount_currency_if_required(input_amount, input_currency, kb_payment_id)

      converted_currency = Killbill::PaypalExpress.converted_currency(input_currency)
      return [input_amount, input_currency] if converted_currency.nil?

      kb_payment = @kb_apis.payment_api.get_payment(kb_payment_id, false, @kb_apis.create_context)

      currency_conversion = @kb_apis.currency_conversion_api.get_currency_conversion(converted_currency, kb_payment.effective_date)
      rates = currency_conversion.rates
      found = rates.select do |r|
        r.currency.to_s.upcase.to_sym == input_currency.to_s.upcase.to_sym
      end

      if found.nil? || found.empty?
        @logger.warn "Failed to find converted currency #{converted_currency} for input currency #{input_currency}"
        return [input_amount, input_currency]
      end

      # conversion rounding ?
      conversion_rate = found[0].value
      output_amount =  input_amount * conversion_rate
      return [output_amount.to_i, converted_currency]
    end

    def save_response_and_transaction(paypal_express_response, api_call, kb_payment_id=nil, amount_in_cents=0, currency=nil)
      @logger.warn "Unsuccessful #{api_call}: #{paypal_express_response.message}" unless paypal_express_response.success?

      # Save the response to our logs
      response = PaypalExpressResponse.from_response(api_call, kb_payment_id, paypal_express_response)
      response.save!

      if response.success and !kb_payment_id.blank? and !response.authorization.blank?
        # Record the transaction
        transaction = response.create_paypal_express_transaction!(:amount_in_cents => amount_in_cents,
                                                                  :currency => currency,
                                                                  :api_call => api_call,
                                                                  :kb_payment_id => kb_payment_id,
                                                                  :paypal_express_txn_id => response.authorization)
        @logger.debug "Recorded transaction: #{transaction.inspect}"
      end
      response
    end
  end
end
