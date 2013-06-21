module Killbill::PaypalExpress
  class PaypalExpressResponse < ActiveRecord::Base
    has_one :paypal_express_transaction
    attr_accessible :api_call,
                    :kb_payment_id,
                    :message,
                    # transaction_id, authorization_id (reauthorization) or refund_transaction_id
                    :authorization,
                    :fraud_review,
                    :test,
                    :token,
                    :payer_id,
                    :billing_agreement_id,
                    :payer_name,
                    :payer_email,
                    :payer_country,
                    :contact_phone,
                    :ship_to_address_name,
                    :ship_to_address_company,
                    :ship_to_address_address1,
                    :ship_to_address_address2,
                    :ship_to_address_city,
                    :ship_to_address_state,
                    :ship_to_address_country,
                    :ship_to_address_zip,
                    :ship_to_address_phone,
                    :receiver_info_business,
                    :receiver_info_receiver,
                    :receiver_info_receiverid,
                    :payment_info_transactionid,
                    :payment_info_parenttransactionid,
                    :payment_info_receiptid,
                    :payment_info_transactiontype,
                    :payment_info_paymenttype,
                    :payment_info_paymentdate,
                    :payment_info_grossamount,
                    :payment_info_feeamount,
                    :payment_info_taxamount,
                    :payment_info_exchangerate,
                    :payment_info_paymentstatus,
                    :payment_info_pendingreason,
                    :payment_info_reasoncode,
                    :payment_info_protectioneligibility,
                    :payment_info_protectioneligibilitytype,
                    :payment_info_shipamount,
                    :payment_info_shiphandleamount,
                    :payment_info_shipdiscount,
                    :payment_info_insuranceamount,
                    :payment_info_subject,
                    :avs_result_code,
                    :avs_result_message,
                    :avs_result_street_match,
                    :avs_result_postal_match,
                    :cvv_result_code,
                    :cvv_result_message,
                    :success

    def self.from_response(api_call, kb_payment_id, response)
      PaypalExpressResponse.new({
                                    :api_call => api_call,
                                    :kb_payment_id => kb_payment_id,
                                    :message => response.message,
                                    :authorization => response.authorization,
                                    :fraud_review => response.fraud_review?,
                                    :test => response.test?,
                                    :token => response.token,
                                    :payer_id => response.payer_id,
                                    :billing_agreement_id => response.params['billing_agreement_id'],
                                    :payer_name => response.name,
                                    :payer_email => response.email,
                                    :payer_country => response.payer_country,
                                    :contact_phone => response.contact_phone,
                                    :ship_to_address_name => response.address['name'],
                                    :ship_to_address_company => response.address['company'],
                                    :ship_to_address_address1 => response.address['address1'],
                                    :ship_to_address_address2 => response.address['address2'],
                                    :ship_to_address_city => response.address['city'],
                                    :ship_to_address_state => response.address['state'],
                                    :ship_to_address_country => response.address['country'],
                                    :ship_to_address_zip => response.address['zip'],
                                    :ship_to_address_phone => response.address['phone'],
                                    :receiver_info_business => receiver_info(response)['Business'],
                                    :receiver_info_receiver => receiver_info(response)['Receiver'],
                                    :receiver_info_receiverid => receiver_info(response)['ReceiverID'],
                                    :payment_info_transactionid => payment_info(response)['TransactionID'],
                                    :payment_info_parenttransactionid => payment_info(response)['ParentTransactionID'],
                                    :payment_info_receiptid => payment_info(response)['ReceiptID'],
                                    :payment_info_transactiontype => payment_info(response)['TransactionType'],
                                    :payment_info_paymenttype => payment_info(response)['PaymentType'],
                                    :payment_info_paymentdate => payment_info(response)['PaymentDate'],
                                    :payment_info_grossamount => payment_info(response)['GrossAmount'],
                                    :payment_info_feeamount => payment_info(response)['FeeAmount'],
                                    :payment_info_taxamount => payment_info(response)['TaxAmount'],
                                    :payment_info_exchangerate => payment_info(response)['ExchangeRate'],
                                    :payment_info_paymentstatus => payment_info(response)['PaymentStatus'],
                                    :payment_info_pendingreason => payment_info(response)['PendingReason'],
                                    :payment_info_reasoncode => payment_info(response)['ReasonCode'],
                                    :payment_info_protectioneligibility => payment_info(response)['ProtectionEligibility'],
                                    :payment_info_protectioneligibilitytype => payment_info(response)['ProtectionEligibilityType'],
                                    :payment_info_shipamount => payment_info(response)['ShipAmount'],
                                    :payment_info_shiphandleamount => payment_info(response)['ShipHandleAmount'],
                                    :payment_info_shipdiscount => payment_info(response)['ShipDiscount'],
                                    :payment_info_insuranceamount => payment_info(response)['InsuranceAmount'],
                                    :payment_info_subject => payment_info(response)['Subject'],
                                    :avs_result_code => response.avs_result.kind_of?(ActiveMerchant::Billing::AVSResult) ? response.avs_result.code : response.avs_result['code'],
                                    :avs_result_message => response.avs_result.kind_of?(ActiveMerchant::Billing::AVSResult) ? response.avs_result.message : response.avs_result['message'],
                                    :avs_result_street_match => response.avs_result.kind_of?(ActiveMerchant::Billing::AVSResult) ? response.avs_result.street_match : response.avs_result['street_match'],
                                    :avs_result_postal_match => response.avs_result.kind_of?(ActiveMerchant::Billing::AVSResult) ? response.avs_result.postal_match : response.avs_result['postal_match'],
                                    :cvv_result_code => response.cvv_result.kind_of?(ActiveMerchant::Billing::CVVResult) ? response.cvv_result.code : response.cvv_result['code'],
                                    :cvv_result_message => response.cvv_result.kind_of?(ActiveMerchant::Billing::CVVResult) ? response.cvv_result.message : response.cvv_result['message'],
                                    :success => response.success?
                                })
    end

    def to_express_checkout_url
      url = Killbill::PaypalExpress.test ? Killbill::PaypalExpress.paypal_sandbox_url : Killbill::PaypalExpress.paypal_production_url
      "#{url}?cmd=_express-checkout&token=#{token}"
    end

    def to_payment_response
      to_killbill_response :payment
    end

    def to_refund_response
      to_killbill_response :refund
    end

    private

    def to_killbill_response(type)
      if paypal_express_transaction.nil?
        # payment_info_grossamount is e.g. "100.00" - we need to convert it in cents
        amount_in_cents = payment_info_grossamount ? (payment_info_grossamount.to_f * 100).to_i : nil
        created_date = created_at
        first_payment_reference_id = nil
        second_payment_reference_id = nil
      else
        amount_in_cents = paypal_express_transaction.amount_in_cents
        created_date = paypal_express_transaction.created_at
        first_payment_reference_id = paypal_express_transaction.paypal_express_txn_id
        second_payment_reference_id = paypal_express_transaction.id.to_s
      end

      effective_date = created_date
      gateway_error = message
      gateway_error_code = nil

      if type == :payment
        p_info_plugin = Killbill::Plugin::Model::PaymentInfoPlugin.new
        p_info_plugin.amount = amount_in_cents
        p_info_plugin.created_date = created_date
        p_info_plugin.effective_date = effective_date
        p_info_plugin.status = (success ? :PROCESSED : :ERROR)
        p_info_plugin.gateway_error = gateway_error
        p_info_plugin.gateway_error_code = gateway_error_code
        p_info_plugin.first_payment_reference_id = first_payment_reference_id
        p_info_plugin.second_payment_reference_id = second_payment_reference_id
        p_info_plugin
      else
        r_info_plugin = Killbill::Plugin::Model::RefundInfoPlugin.new
        r_info_plugin.amount = amount_in_cents
        r_info_plugin.created_date = created_date
        r_info_plugin.effective_date = effective_date
        r_info_plugin.status = (success ? :PROCESSED : :ERROR)
        r_info_plugin.gateway_error = gateway_error
        r_info_plugin.gateway_error_code = gateway_error_code
        r_info_plugin.reference_id = first_payment_reference_id
        r_info_plugin
      end
    end

    # Paypal has various response formats depending on the API call and the ActiveMerchant Paypal plugin doesn't try to
    # unify them, hence the gymnastic here

    def self.receiver_info(response)
      response.params['ReceiverInfo'] || (response.params['PaymentTransactionDetails'] || {})['ReceiverInfo'] || {}
    end

    def self.payment_info(response)
      response.params['PaymentInfo'] || (response.params['PaymentTransactionDetails'] || {})['PaymentInfo'] || {}
    end
  end
end
