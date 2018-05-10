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
# ActiveRecord::Base.logger = Logger.new(STDOUT)
# Create the schema
require File.expand_path(File.dirname(__FILE__) + '../../db/schema.rb')


def validate_details_for(kb_payment_id, transaction_type, payer_id)
  details_for = ::Killbill::PaypalExpress::PaypalExpressResponse.where(:kb_payment_id => kb_payment_id).where(:api_call => :details_for).last
  details_for.message.should == "Success"
  details_for.transaction_type.to_sym.should == transaction_type.to_sym
  details_for.payer_id.should == payer_id
  details_for.payer_name.should be_nil
end


class PaypalExpressJavaPaymentApi < ::Killbill::Plugin::ActiveMerchant::RSpec::FakeJavaPaymentApi

  def initialize(plugin)
    super()
    @plugin = plugin
  end

  def get_account_payment_methods(kb_account_id, plugin_info, properties, context)
    [OpenStruct.new(:plugin_name => 'killbill-paypal-express', :id => SecureRandom.uuid)]
  end

  def create_purchase(kb_account, kb_payment_method_id, kb_payment_id, amount, currency, payment_external_key, payment_transaction_external_key, properties, context)
    kb_payment = add_payment(kb_payment_id || SecureRandom.uuid, SecureRandom.uuid, payment_transaction_external_key, :PURCHASE)

    rcontext = context.to_ruby(context)
    @plugin.purchase_payment(kb_account.id, kb_payment.id, kb_payment.transactions.last.id, kb_payment_method_id, amount, currency, properties, rcontext)

    kb_payment
  end

  def create_authorization(kb_account, kb_payment_method_id, kb_payment_id, amount, currency, payment_external_key, payment_transaction_external_key, properties, context)
    kb_payment = add_payment(kb_payment_id || SecureRandom.uuid, SecureRandom.uuid, payment_transaction_external_key, :AUTHORIZE)

    rcontext = context.to_ruby(context)
    @plugin.authorize_payment(kb_account.id, kb_payment.id, kb_payment.transactions.last.id, kb_payment_method_id, amount, currency, properties, rcontext)

    kb_payment
  end

  def delete_all_payments
    @payments = []
  end
end
