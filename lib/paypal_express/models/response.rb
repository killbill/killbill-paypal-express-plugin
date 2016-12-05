module Killbill #:nodoc:
  module PaypalExpress #:nodoc:
    class PaypalExpressResponse < ::Killbill::Plugin::ActiveMerchant::ActiveRecord::Response

      self.table_name = 'paypal_express_responses'

      has_one :paypal_express_transaction

      def self.ignore_none(value)
        value == 'none' ? nil : value
      end

      def self.from_response(api_call, kb_account_id, kb_payment_id, kb_payment_transaction_id, transaction_type, payment_processor_account_id, kb_tenant_id, response, extra_params = {}, model = ::Killbill::PaypalExpress::PaypalExpressResponse)
        super(api_call,
              kb_account_id,
              kb_payment_id,
              kb_payment_transaction_id,
              transaction_type,
              payment_processor_account_id,
              kb_tenant_id,
              response,
              {
                  :token                                  => extract(response, 'Token'),
                  :payer_id                               => extract(response, 'PayerInfo', 'PayerID'),
                  :billing_agreement_id                   => extract(response, 'billing_agreement_id'),
                  :payer_name                             => [extract(response, 'PayerInfo', 'PayerName', 'FirstName'), extract(response, 'PayerInfo', 'PayerName', 'MiddleName'), extract(response, 'PayerInfo', 'PayerName', 'LastName')].compact.join(' '),
                  :payer_email                            => extract(response, 'PayerInfo', 'Payer'),
                  :payer_country                          => extract(response, 'PayerInfo', 'PayerCountry'),
                  :contact_phone                          => extract(response, 'ContactPhone'),
                  :ship_to_address_name                   => extract(response, 'ShipToAddress', 'Name'),
                  :ship_to_address_company                => extract(response, 'PayerInfo', 'PayerBusiness'),
                  :ship_to_address_address1               => extract(response, 'ShipToAddress', 'Street1'),
                  :ship_to_address_address2               => extract(response, 'ShipToAddress', 'Street2'),
                  :ship_to_address_city                   => extract(response, 'ShipToAddress', 'CityName'),
                  :ship_to_address_state                  => extract(response, 'ShipToAddress', 'StateOrProvince'),
                  :ship_to_address_country                => extract(response, 'ShipToAddress', 'Country'),
                  :ship_to_address_zip                    => extract(response, 'ShipToAddress', 'PostalCode'),
                  :ship_to_address_phone                  => (extract(response, 'ContactPhone') || extract(response, 'ShipToAddress', 'Phone')),
                  :receiver_info_business                 => (extract(response, 'ReceiverInfo', 'Business') || extract(response, 'PaymentTransactionDetails', 'ReceiverInfo', 'Business')),
                  :receiver_info_receiver                 => (extract(response, 'ReceiverInfo', 'Receiver') || extract(response, 'PaymentTransactionDetails', 'ReceiverInfo', 'Receiver')),
                  :receiver_info_receiverid               => (extract(response, 'ReceiverInfo', 'ReceiverID') || extract(response, 'PaymentTransactionDetails', 'ReceiverInfo', 'ReceiverID')),
                  :payment_info_transactionid             => (extract(response, 'PaymentInfo', 'TransactionID') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'TransactionID')),
                  :payment_info_parenttransactionid       => (extract(response, 'PaymentInfo', 'ParentTransactionID') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'ParentTransactionID')),
                  :payment_info_receiptid                 => (extract(response, 'PaymentInfo', 'ReceiptID') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'ReceiptID')),
                  :payment_info_transactiontype           => (extract(response, 'PaymentInfo', 'TransactionType') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'TransactionType')),
                  :payment_info_paymenttype               => (extract(response, 'PaymentInfo', 'PaymentType') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'PaymentType')),
                  :payment_info_paymentdate               => (extract(response, 'PaymentInfo', 'PaymentDate') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'PaymentDate')),
                  :payment_info_grossamount               => (extract(response, 'PaymentInfo', 'GrossAmount') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'GrossAmount')),
                  :payment_info_feeamount                 => (extract(response, 'PaymentInfo', 'FeeAmount') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'FeeAmount')),
                  :payment_info_taxamount                 => (extract(response, 'PaymentInfo', 'TaxAmount') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'TaxAmount')),
                  :payment_info_exchangerate              => (extract(response, 'PaymentInfo', 'ExchangeRate') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'ExchangeRate')),
                  :payment_info_paymentstatus             => (extract(response, 'PaymentInfo', 'PaymentStatus') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'PaymentStatus')),
                  :payment_info_pendingreason             => (extract(response, 'PaymentInfo', 'PendingReason') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'PendingReason')),
                  :payment_info_reasoncode                => (ignore_none(extract(response, 'PaymentInfo', 'ReasonCode')) || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'ReasonCode') || extract(response, 'error_codes')),
                  :payment_info_protectioneligibility     => (extract(response, 'PaymentInfo', 'ProtectionEligibility') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'ProtectionEligibility')),
                  :payment_info_protectioneligibilitytype => (extract(response, 'PaymentInfo', 'ProtectionEligibilityType') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'ProtectionEligibilityType')),
                  :payment_info_shipamount                => (extract(response, 'PaymentInfo', 'ShipAmount') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'ShipAmount')),
                  :payment_info_shiphandleamount          => (extract(response, 'PaymentInfo', 'ShipHandleAmount') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'ShipHandleAmount')),
                  :payment_info_shipdiscount              => (extract(response, 'PaymentInfo', 'ShipDiscount') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'ShipDiscount')),
                  :payment_info_insuranceamount           => (extract(response, 'PaymentInfo', 'InsuranceAmount') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'InsuranceAmount')),
                  :payment_info_subject                   => (extract(response, 'PaymentInfo', 'Subject') || extract(response, 'PaymentTransactionDetails', 'PaymentInfo', 'Subject'))
              }.merge!(extra_params),
              model)
      end

      def self.last_token(kb_account_id, kb_tenant_id)
        response = where(:api_call => 'initiate_express_checkout',
                         :success => true,
                         :kb_account_id => kb_account_id,
                         :kb_tenant_id => kb_tenant_id).last
        response.nil? ? nil : response.token
      end

      def self.initial_payment_account_processor_id(kb_account_id, kb_tenant_id, token)
        return nil if token.blank?
        response = where(:api_call => 'initiate_express_checkout',
                         :success => true,
                         :kb_account_id => kb_account_id,
                         :kb_tenant_id => kb_tenant_id,
                         :token => token).last
        response.nil? ? nil : response.payment_processor_account_id
      end

      def self.cancel_pending_payment(transaction_plugin_info)
         where( :api_call => 'build_form_descriptor',
                :kb_payment_id => transaction_plugin_info.kb_payment_id,
                :kb_payment_transaction_id => transaction_plugin_info.kb_transaction_payment_id).update_all( :success => false,
                                                                                                             :updated_at => Time.now.utc,
                                                                                                             :message => { :payment_plugin_status => :CANCELED, :exception_message => 'Token expired. Payment Canceled by Janitor.' }.to_json)
      end

      def gateway_error_code
        payment_info_reasoncode
      end

      def to_transaction_info_plugin(transaction=nil)
        t_info_plugin = super(transaction)

        t_info_plugin.properties << create_plugin_property('message', token)
        t_info_plugin.properties << create_plugin_property('payerId', payer_id)
        t_info_plugin.properties << create_plugin_property('baid', billing_agreement_id)
        t_info_plugin.properties << create_plugin_property('payerName', payer_name)
        t_info_plugin.properties << create_plugin_property('payerEmail', payer_email)
        t_info_plugin.properties << create_plugin_property('payerCountry', payer_country)
        t_info_plugin.properties << create_plugin_property('contactPhone', contact_phone)
        t_info_plugin.properties << create_plugin_property('shipToAddressName', ship_to_address_name)
        t_info_plugin.properties << create_plugin_property('shipToAddressPayerBusiness', ship_to_address_company)
        t_info_plugin.properties << create_plugin_property('shipToAddressStreet1', ship_to_address_address1)
        t_info_plugin.properties << create_plugin_property('shipToAddressStreet2', ship_to_address_address2)
        t_info_plugin.properties << create_plugin_property('shipToAddressCityName', ship_to_address_city)
        t_info_plugin.properties << create_plugin_property('shipToAddressStateOrProvince', ship_to_address_state)
        t_info_plugin.properties << create_plugin_property('shipToAddressCountry', ship_to_address_country)
        t_info_plugin.properties << create_plugin_property('shipToAddressPostalCode', ship_to_address_zip)
        t_info_plugin.properties << create_plugin_property('shipToAddressContactPhone', ship_to_address_phone)
        t_info_plugin.properties << create_plugin_property('receiverInfoBusiness', receiver_info_business)
        t_info_plugin.properties << create_plugin_property('receiverInfoReceiver', receiver_info_receiver)
        t_info_plugin.properties << create_plugin_property('receiverInfoReceiverID', receiver_info_receiverid)
        t_info_plugin.properties << create_plugin_property('paymentInfoTransactionID', payment_info_transactionid)
        t_info_plugin.properties << create_plugin_property('paymentInfoParentTransactionID', payment_info_parenttransactionid)
        t_info_plugin.properties << create_plugin_property('paymentInfoReceiptID', payment_info_receiptid)
        t_info_plugin.properties << create_plugin_property('paymentInfoTransactionType', payment_info_transactiontype)
        t_info_plugin.properties << create_plugin_property('paymentInfoPaymentType', payment_info_paymenttype)
        t_info_plugin.properties << create_plugin_property('paymentInfoPaymentDate', payment_info_paymentdate)
        t_info_plugin.properties << create_plugin_property('paymentInfoGrossAmount', payment_info_grossamount)
        t_info_plugin.properties << create_plugin_property('paymentInfoFeeAmount', payment_info_feeamount)
        t_info_plugin.properties << create_plugin_property('paymentInfoTaxAmount', payment_info_taxamount)
        t_info_plugin.properties << create_plugin_property('paymentInfoExchangeRate', payment_info_exchangerate)
        t_info_plugin.properties << create_plugin_property('paymentInfoPaymentStatus', payment_info_paymentstatus)
        t_info_plugin.properties << create_plugin_property('paymentInfoPendingReason', payment_info_pendingreason)
        t_info_plugin.properties << create_plugin_property('paymentInfoReasonCode', payment_info_reasoncode)
        t_info_plugin.properties << create_plugin_property('paymentInfoProtectionEligibility', payment_info_protectioneligibility)
        t_info_plugin.properties << create_plugin_property('paymentInfoProtectionEligibilityType', payment_info_protectioneligibilitytype)
        t_info_plugin.properties << create_plugin_property('paymentInfoShipAmount', payment_info_shipamount)
        t_info_plugin.properties << create_plugin_property('paymentInfoShipHandleAmount', payment_info_shiphandleamount)
        t_info_plugin.properties << create_plugin_property('paymentInfoShipDiscount', payment_info_shipdiscount)
        t_info_plugin.properties << create_plugin_property('paymentInfoInsuranceAmount', payment_info_insuranceamount)
        t_info_plugin.properties << create_plugin_property('paymentInfoSubject', payment_info_subject)
        t_info_plugin.properties << create_plugin_property('paypalExpressResponseId', id)

        t_info_plugin
      end
    end
  end
end
