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

    def self.search(search_key)
      search_columns = [
                         :paypal_express_payer_id,
                         :paypal_express_baid,
                         :paypal_express_token
                       ]
      query = search_columns.map(&:to_s).join(' like ? or ') + ' like ?'
      where(query, *search_columns.map { |e| "%#{search_key}%" })
    end

    def to_payment_method_response
      properties = []
      properties << create_pm_kv_info('payerId', paypal_express_payer_id)
      properties << create_pm_kv_info('baid', paypal_express_baid)
      properties << create_pm_kv_info('token', paypal_express_token)

      # We're pretty much guaranteed to have a (single) entry for details_for, since it was called during add_payment_method
      details_for = PaypalExpressResponse.find_all_by_api_call_and_token('details_for', paypal_express_token).last
      unless details_for.nil?
        properties << create_pm_kv_info('payerName', details_for.payer_name)
        properties << create_pm_kv_info('payerEmail', details_for.payer_email)
        properties << create_pm_kv_info('payerCountry', details_for.payer_country)
        properties << create_pm_kv_info('contactPhone', details_for.contact_phone)
        properties << create_pm_kv_info('shipToAddressName', details_for.ship_to_address_name)
        properties << create_pm_kv_info('shipToAddressCompany', details_for.ship_to_address_company)
        properties << create_pm_kv_info('shipToAddressAddress1', details_for.ship_to_address_address1)
        properties << create_pm_kv_info('shipToAddressAddress2', details_for.ship_to_address_address2)
        properties << create_pm_kv_info('shipToAddressCity', details_for.ship_to_address_city)
        properties << create_pm_kv_info('shipToAddressState', details_for.ship_to_address_state)
        properties << create_pm_kv_info('shipToAddressCountry', details_for.ship_to_address_country)
        properties << create_pm_kv_info('shipToAddressZip', details_for.ship_to_address_zip)
      end

      pm_plugin = Killbill::Plugin::Model::PaymentMethodPlugin.new
      pm_plugin.kb_payment_method_id = kb_payment_method_id
      pm_plugin.external_payment_method_id = external_payment_method_id
      pm_plugin.is_default_payment_method = is_default
      pm_plugin.properties = properties
      pm_plugin.type = 'PayPal'

      pm_plugin
    end

    def to_payment_method_info_response
      pm_info_plugin = Killbill::Plugin::Model::PaymentMethodInfoPlugin.new
      pm_info_plugin.account_id = kb_account_id
      pm_info_plugin.payment_method_id = kb_payment_method_id
      pm_info_plugin.is_default = is_default
      pm_info_plugin.external_payment_method_id = external_payment_method_id
      pm_info_plugin
    end

    def is_default
      # No concept of default payment method in Paypal Express
      false
    end

    private

    def create_pm_kv_info(key, value)
      prop = Killbill::Plugin::Model::PaymentMethodKVInfo.new
      prop.key = key
      prop.value = value
      prop
    end
  end
end
