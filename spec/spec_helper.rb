require 'bundler'
require 'paypal_express'
require 'killbill/helpers/active_merchant/killbill_spec_helper'

require 'logger'

require 'rspec'

RSpec.configure do |config|
  config.color_enabled = true
  config.tty = true
  config.formatter = 'documentation'
end

require 'active_record'
ActiveRecord::Base.establish_connection(
    :adapter => 'sqlite3',
    :database => 'test.db'
)
# For debugging
#ActiveRecord::Base.logger = Logger.new(STDOUT)
# Create the schema
require File.expand_path(File.dirname(__FILE__) + '../../db/schema.rb')

class PaypalExpressJavaPaymentApi < ::Killbill::Plugin::ActiveMerchant::RSpec::FakeJavaPaymentApi
  def get_account_payment_methods(kb_account_id, plugin_info, properties, context)
    [OpenStruct.new(:plugin_name => 'killbill-paypal-express', :id => SecureRandom.uuid)]
  end

  def create_purchase(kb_account, kb_payment_method_id, kb_payment_id, amount, currency, payment_external_key, payment_transaction_external_key, properties, context)
    add_payment(SecureRandom.uuid, SecureRandom.uuid, payment_transaction_external_key, :PURCHASE)
  end
end
