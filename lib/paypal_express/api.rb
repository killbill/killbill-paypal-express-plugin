module Killbill::PaypalExpress
  class PaymentPlugin < Killbill::Plugin::Payment
    def start_plugin
      Killbill::PaypalExpress.initialize! "#{@root}/paypal_express.yml", @logger
      @gateway = Killbill::PaypalExpress.gateway

      super

      @logger.info "Killbill::PaypalExpress::PaymentPlugin started"
    end

    def get_name
      'paypal_express'
    end

    def charge(kb_payment_id, kb_payment_method_id, amount_in_cents, options = {})
      # TODO
      # options[:currency] ||=

      # Required arguments
      if options[:token].blank? or options[:payer_id].blank?
        payment_method = PaypalExpressPaymentMethod.from_kb_payment_method_id(kb_payment_method_id)
        options[:payer_id] ||= payment_method.paypal_express_payer_id
        options[:token] ||= payment_method.paypal_express_token
      end

      # Go to Paypal
      paypal_response = @gateway.purchase amount_in_cents, options
      response = save_response_and_transaction paypal_response, :charge, kb_payment_id, amount_in_cents

      response.to_payment_response
    end

    def refund(kb_payment_id, amount_in_cents, options = {})
      # Find one successful charge which amount is at least the amount we are trying to refund
      paypal_express_transaction = PaypalExpressTransaction.where("paypal_express_transactions.amount_in_cents >= ?", amount_in_cents).find_last_by_api_call_and_kb_payment_id(:charge, kb_payment_id)
      raise "Unable to find Paypal Express transaction id for payment #{kb_payment_id}" if paypal_express_transaction.nil?

      # TODO
      # options[:currency] ||=
      options[:refund_type] ||= paypal_express_transaction.amount_in_cents != amount_in_cents ? 'Partial' : 'Full'

      identification = paypal_express_transaction.paypal_express_txn_id

      # Go to Paypal
      paypal_response = @gateway.refund amount_in_cents, identification, options
      response = save_response_and_transaction paypal_response, :refund, kb_payment_id, amount_in_cents

      response.to_refund_response
    end

    def get_payment_info(kb_payment_id, options = {})
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

    def add_payment_method(kb_account_id, kb_payment_method_id, payment_method_props, set_default=false, options = {})
      token = payment_method_props.value('token')
      return false if token.nil?

      # The payment method should have been created during the setup step (see private api)
      payment_method = PaypalExpressPaymentMethod.from_kb_account_id_and_token(kb_account_id, token)

      # Go to Paypal
      paypal_express_details_response = @gateway.details_for token
      response = save_response_and_transaction paypal_express_details_response, :details_for
      return false unless response.success?

      unless response.payer_id.nil?
        payment_method.kb_payment_method_id = kb_payment_method_id
        payment_method.paypal_express_payer_id = response.payer_id
        payment_method.save!
        true
      else
        logger.warn "Unable to retrieve Payer id details for token #{token} (account #{kb_account_id})"
        false
      end
    end

    def delete_payment_method(kb_payment_method_id, options = {})
    end

    def get_payment_method_detail(kb_account_id, kb_payment_method_id, options = {})
    end

    def get_payment_methods(kb_account_id, options = {})
    end

    def create_account(killbill_account, options = {})
    end

    private

    def save_response_and_transaction(paypal_express_response, api_call, kb_payment_id=nil, amount_in_cents=0)
      @logger.warn "Unsuccessful #{api_call}: #{paypal_express_response.message}" unless paypal_express_response.success?

      # Save the response to our logs
      response = PaypalExpressResponse.from_response(api_call, kb_payment_id, paypal_express_response)
      response.save!

      if response.success and !response.authorization.blank?
        # Record the transaction
        transaction = response.create_paypal_express_transaction!(:amount_in_cents => amount_in_cents, :api_call => api_call, :kb_payment_id => kb_payment_id, :paypal_express_txn_id => response.authorization)
        @logger.debug "Recorded transaction: #{transaction.inspect}"
      end
      response
    end
  end
end
