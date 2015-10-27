require 'spec_helper'

ActiveMerchant::Billing::Base.mode = :test

describe Killbill::PaypalExpress::PaymentPlugin do

  include ::Killbill::Plugin::ActiveMerchant::RSpec

  before(:all) do
    @plugin = build_plugin(::Killbill::PaypalExpress::PaymentPlugin, 'paypal_express')
    svcs = @plugin.kb_apis.proxied_services
    svcs[:payment_api] = PaypalExpressJavaPaymentApi.new
    @plugin.kb_apis = ::Killbill::Plugin::KillbillApi.new('paypal_express', svcs)
    @plugin.start_plugin

    @call_context = build_call_context

    @properties = []
    @amount = BigDecimal.new('100')
    @currency = 'USD'

    kb_account_id = SecureRandom.uuid
    external_key, kb_account_id = create_kb_account(kb_account_id, @plugin.kb_apis.proxied_services[:account_user_api])

    @pm = create_payment_method(::Killbill::PaypalExpress::PaypalExpressPaymentMethod, kb_account_id, @call_context.tenant_id, [])

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

    # For HPP we need a new token for every test
    response = create_token(@pm.kb_account_id, @call_context.tenant_id, @amount, @currency)
    token = response.token
    payer_id = response.payer_id
    print "\nPlease go to #{@plugin.to_express_checkout_url(response, @call_context.tenant_id)} to proceed and press any key to continue...
Note: you need to log-in with a paypal sandbox account (create one here: https://developer.paypal.com/webapps/developer/applications/accounts)\n"
    $stdin.gets

    # add token to properties after creating the PM so we don't store it
    @properties = []
    @properties << build_property('token', token)
    @properties << build_property('payer_id', payer_id)

    kb_payment_id = SecureRandom.uuid
    # Prepare two transactions for purchase & refund
    @kb_payment = @plugin.kb_apis.proxied_services[:payment_api].add_payment(kb_payment_id)
    @kb_payment = @plugin.kb_apis.proxied_services[:payment_api].add_payment(kb_payment_id)
    @kb_payment.transactions[0].transaction_status = :PENDING
  end

  after(:each) do
    @plugin.stop_plugin
    @plugin.start_plugin
  end

  it 'should be able to charge and refund with a pending payment' do
    properties = Array.new(@properties)
    properties << build_property('kb_payment_id', @kb_payment.id)

    payment_response = @plugin.purchase_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :PURCHASE

    # Try a full refund
    refund_response = @plugin.refund_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[1].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    refund_response.status.should eq(:PROCESSED), refund_response.gateway_error
    refund_response.amount.should == @amount
    refund_response.transaction_type.should == :REFUND
  end

  it 'should be able to pay and refund' do
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



  it 'should generate forms correctly' do
    context = @plugin.kb_apis.create_context(@call_context.tenant_id)
    fields  = @plugin.hash_to_properties(
                :order_id => '1234',
                :amount   => 10
              )
    form    = @plugin.build_form_descriptor(@pm.kb_account_id, fields, [], context)

    form.kb_account_id.should == @pm.kb_account_id
    form.form_method.should   == 'POST'
    form.form_url.should start_with('https://www.sandbox.paypal.com/cgi-bin/webscr')
    form.properties.select{|prop| prop.key == 'kb_payment_id'}.should be_empty
  end

  it 'should generate forms and pending payments correctly' do
    context              = @plugin.kb_apis.create_context(@call_context.tenant_id)
    payment_external_key = SecureRandom.uuid

    fields = @plugin.hash_to_properties(
      :order_id => '1234',
      :amount   => 10
    )

    properties = @plugin.hash_to_properties(
      :payment_external_key   => payment_external_key,
      :create_pending_payment => true
    )

    form = @plugin.build_form_descriptor(@pm.kb_account_id, fields, properties, context)

    form.kb_account_id.should == @pm.kb_account_id
    form.form_method.should   == 'POST'
    form.form_url.should start_with('https://www.sandbox.paypal.com/cgi-bin/webscr')
    form.properties.select{|prop| prop.key == 'kb_payment_id'}.should_not be_empty
  end

  private

  def create_token(kb_account_id, kb_tenant_id, amount, currency)
    private_plugin = ::Killbill::PaypalExpress::PrivatePaymentPlugin.new
    response       = private_plugin.initiate_express_checkout(kb_account_id, kb_tenant_id, amount, currency, false)
    response.success.should be_true
    response
  end
end
