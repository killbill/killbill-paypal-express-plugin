module Killbill::PaypalExpress
  class PaypalExpressPaymentMethod < ActiveRecord::Base
    attr_accessible :kb_account_id,
                    :kb_payment_method_id,
                    :paypal_express_payer_id,
                    :paypal_express_baid,
                    :paypal_express_token

    alias_attribute :external_payment_method_id, :paypal_express_baid

    def self.from_kb_account_id(kb_account_id)
      find_all_by_kb_account_id_and_is_deleted(kb_account_id, false)
    end

    def self.from_kb_payment_method_id(kb_payment_method_id)
      payment_methods = find_all_by_kb_payment_method_id_and_is_deleted(kb_payment_method_id, false)
      raise "No payment method found for payment method #{kb_payment_method_id}" if payment_methods.empty?
      raise "Killbill payment method mapping to multiple active PaypalExpress tokens for payment method #{kb_payment_method_id}" if payment_methods.size > 1
      payment_methods[0]
    end

    # Used to complete the checkout process
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
      properties = []
      properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'payerId', paypal_express_payer_id)
      properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'baid', paypal_express_baid)
      properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'token', paypal_express_token)

      # We're pretty much guaranteed to have a (single) entry for details_for, since it was called during add_payment_method
      details_for = PaypalExpressResponse.find_all_by_api_call_and_token('details_for', paypal_express_token).last
      unless details_for.nil?
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'payerName', details_for.payer_name)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'payerEmail', details_for.payer_email)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'payerCountry', details_for.payer_country)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'contactPhone', details_for.contact_phone)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'shipToAddressName', details_for.ship_to_address_name)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'shipToAddressCompany', details_for.ship_to_address_company)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'shipToAddressAddress1', details_for.ship_to_address_address1)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'shipToAddressAddress2', details_for.ship_to_address_address2)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'shipToAddressCity', details_for.ship_to_address_city)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'shipToAddressState', details_for.ship_to_address_state)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'shipToAddressCountry', details_for.ship_to_address_country)
        properties << Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, 'shipToAddressZip', details_for.ship_to_address_zip)
      end

      Killbill::Plugin::Model::PaymentMethodPlugin.new(external_payment_method_id,
                                                       is_default,
                                                       properties,
                                                       nil,
                                                       'PayPal',
                                                       nil,
                                                       nil,
                                                       nil,
                                                       nil,
                                                       nil,
                                                       nil,
                                                       nil,
                                                       nil,
                                                       nil,
                                                       nil,
                                                       nil)
    end

    def to_payment_method_info_response
      Killbill::Plugin::Model::PaymentMethodInfoPlugin.new(kb_account_id, kb_payment_method_id, is_default, external_payment_method_id)
    end

    def is_default
      # No concept of default payment method in Paypal Express
      false
    end
  end
end
