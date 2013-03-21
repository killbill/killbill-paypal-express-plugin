module Killbill::PaypalExpress
  class PaypalExpressPaymentMethod < ActiveRecord::Base
    attr_accessible :kb_account_id,
                    :kb_payment_method_id,
                    :paypal_express_payer_id,
                    :paypal_express_token

    def self.from_kb_account_id(kb_account_id)
      find_all_by_kb_account_id_and_is_deleted(kb_account_id, false)
    end

    def self.from_kb_payment_method_id(kb_payment_method_id)
      payment_methods = find_all_by_kb_payment_method_id_and_is_deleted(kb_payment_method_id, false)
      raise "No payment method found for payment method #{kb_payment_method_id}" if payment_methods.empty?
      raise "Killbill payment method mapping to multiple active PaypalExpress tokens for payment method #{kb_payment_method_id}" if payment_methods.size > 1
      payment_methods[0]
    end

    def self.from_kb_account_id_and_token(kb_account_id, token)
      payment_methods = find_all_by_kb_account_id_and_paypal_express_token_and_is_deleted(kb_account_id, token, false)
      raise "No payment method found for account #{kb_account_id}" if payment_methods.empty?
      raise "Paypal token mapping to multiple active PaypalExpress payment methods #{kb_account_id}" if payment_methods.size > 1
      payment_methods[0]
    end

    def self.mark_as_deleted!(kb_payment_method_id)
      payment_method = from_kb_payment_method_id(kb_payment_method_id)
      payment_method.is_deleted = true
      payment_method.save!
    end

    def to_payment_method_response
      external_payment_method_id = paypal_express_token
      # No concept of default payment method in Paypal Express
      is_default = false
      # No extra information is stored in Paypal Express
      properties = []

      Killbill::Plugin::PaymentMethodResponse.new external_payment_method_id, is_default, properties
    end
  end
end
