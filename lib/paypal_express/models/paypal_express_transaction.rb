module Killbill::PaypalExpress
  class PaypalExpressTransaction < ActiveRecord::Base
    belongs_to :paypal_express_response
    attr_accessible :amount_in_cents,
                    :api_call,
                    :kb_payment_id,
                    :paypal_express_txn_id

    def self.from_kb_payment_id(kb_payment_id)
      paypal_express_transactions = find_all_by_api_call_and_kb_payment_id(:charge, kb_payment_id)
      raise "Unable to find Paypal Express transaction id for payment #{kb_payment_id}" if paypal_express_transactions.empty?
      raise "Killbill payment mapping to multiple Paypal Express transactions for payment #{kb_payment_id}" if paypal_express_transactions.size > 1
      paypal_express_transactions[0]
    end
  end
end