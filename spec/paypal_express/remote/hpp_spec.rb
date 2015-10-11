require 'spec_helper'

ActiveMerchant::Billing::Base.mode = :test

describe Killbill::PaypalExpress::PaymentPlugin do

  include ::Killbill::Plugin::ActiveMerchant::RSpec

  before(:all) do
    @plugin = build_plugin(::Killbill::PaypalExpress::PaymentPlugin, 'paypal_express')
    @plugin.start_plugin

    @call_context = build_call_context

    @properties = [build_property('from_hpp', 'true')]
    @amount = BigDecimal.new('100')
    @currency = 'USD'

    kb_account_id = SecureRandom.uuid
    external_key, kb_account_id = create_kb_account(kb_account_id, @plugin.kb_apis.proxied_services[:account_user_api])

    # Initiate the setup process
    response = create_token(kb_account_id, @call_context.tenant_id)
    token = response.token
    payer_id = response.payer_id
    print "\nPlease go to #{@plugin.to_express_checkout_url(response, @call_context.tenant_id)} to proceed and press any key to continue...
Note: you need to log-in with a paypal sandbox account (create one here: https://developer.paypal.com/webapps/developer/applications/accounts)\n"
    $stdin.gets

    @pm = create_payment_method(::Killbill::PaypalExpress::PaypalExpressPaymentMethod, kb_account_id, @call_context.tenant_id, @properties)
    # add token to properties after creating the PM so we don't store it
    @properties << build_property('token', token)
    @properties << build_property('payer_id', payer_id)

    # Verify our table directly. Note that @pm.token is the baid
    payment_methods = ::Killbill::PaypalExpress::PaypalExpressPaymentMethod.from_kb_account_id(kb_account_id, @call_context.tenant_id)
    payment_methods.size.should == 1
    payment_method = payment_methods.first
    payment_method.should_not be_nil
    payment_method.paypal_express_payer_id.should be_nil
    payment_method.token.should be_nil
    payment_method.kb_payment_method_id.should == @pm.kb_payment_method_id
  end

  before(:each) do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.delete_all
    ::Killbill::PaypalExpress::PaypalExpressResponse.delete_all

    kb_payment_id = SecureRandom.uuid
    1.upto(6) do
      @kb_payment = @plugin.kb_apis.proxied_services[:payment_api].add_payment(kb_payment_id)
    end
  end

  after(:each) do
    @plugin.stop_plugin
  end

  it 'should be able to charge and refund' do
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :PURCHASE

    # Try a full refund
    refund_response = @plugin.refund_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[1].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    refund_response.status.should eq(:PROCESSED), refund_response.gateway_error
    refund_response.amount.should == @amount
    refund_response.transaction_type.should == :REFUND
  end

  private

  def create_token(kb_account_id, kb_tenant_id)
    private_plugin = ::Killbill::PaypalExpress::PrivatePaymentPlugin.new
    response       = private_plugin.initiate_express_checkout(kb_account_id, kb_tenant_id)
    response.success.should be_true
    response
  end
end
