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
                    :payer_name,
                    :payer_email,
                    :payer_country,
                    :payer_info,
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
                                  :payer_name => response.name,
                                  :payer_email => response.email,
                                  :payer_country => response.payer_country,
                                  :payer_info => response.info,
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
      to_killbill_response Killbill::Plugin::PaymentResponse
    end

    def to_refund_response
      to_killbill_response Killbill::Plugin::RefundResponse
    end

    private

    def to_killbill_response(klass)
      if paypal_express_transaction.nil?
        amount_in_cents = nil
        created_date = created_at
      else
        amount_in_cents = paypal_express_transaction.amount_in_cents
        created_date = paypal_express_transaction.created_at
      end

      effective_date = created_date
      status = message
      gateway_error = nil
      gateway_error_code = nil

      klass.new(amount_in_cents, created_date, effective_date, status, gateway_error, gateway_error_code)
    end
  end
end
