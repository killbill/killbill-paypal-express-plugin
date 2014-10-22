module Killbill #:nodoc:
  module PaypalExpress #:nodoc:
    class PaypalExpressTransaction < ::Killbill::Plugin::ActiveMerchant::ActiveRecord::Transaction

      self.table_name = 'paypal_express_transactions'

      belongs_to :paypal_express_response

    end
  end
end
