require 'spec_helper'

ActiveMerchant::Billing::Base.mode = :test

describe Killbill::PaypalExpress::PaymentPlugin do

  include ::Killbill::Plugin::ActiveMerchant::RSpec

  before(:all) do
    @plugin = build_plugin(::Killbill::PaypalExpress::PaymentPlugin, 'paypal_express')
    svcs = @plugin.kb_apis.proxied_services
    svcs[:payment_api] = PaypalExpressJavaPaymentApi.new(@plugin)
    @plugin.kb_apis = ::Killbill::Plugin::KillbillApi.new('paypal_express', svcs)
    @plugin.start_plugin

    @call_context = build_call_context

    @amount = BigDecimal.new('100')
    @currency = 'USD'
    @form_fields  = @plugin.hash_to_properties(
        :order_id => '1234',
        :amount   => @amount,
        :currency => @currency
    )

    kb_account_id = SecureRandom.uuid
    create_kb_account(kb_account_id, @plugin.kb_apis.proxied_services[:account_user_api])

    @pm = create_payment_method(::Killbill::PaypalExpress::PaypalExpressPaymentMethod, kb_account_id, @call_context.tenant_id)
  end

  before(:each) do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.delete_all
    ::Killbill::PaypalExpress::PaypalExpressResponse.delete_all
  end

  it 'should generate forms correctly' do
    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, [], @call_context)
    validate_form(form)
    validate_nil_form_property(form, 'kb_payment_id')
    validate_nil_form_property(form, 'kb_transaction_external_key')
    token = validate_form_property(form, 'token')

    # Verify no payment was created in Kill Bill
    @plugin.kb_apis.proxied_services[:payment_api].payments.should be_empty

    validate_token(form)

    properties = []
    properties << build_property('token', token)
    purchase_and_refund(SecureRandom.uuid, SecureRandom.uuid, properties)

    # Verify no extra payment was created in Kill Bill by the plugin
    @plugin.kb_apis.proxied_services[:payment_api].payments.should be_empty
  end

  it 'should generate forms with pending payments correctly' do
    payment_external_key = SecureRandom.uuid
    properties = @plugin.hash_to_properties(
      :transaction_external_key => payment_external_key,
      :create_pending_payment => true
    )

    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    validate_form(form)
    kb_payment_id = validate_form_property(form, 'kb_payment_id')
    validate_form_property(form, 'kb_transaction_external_key', payment_external_key)
    token = validate_form_property(form, 'token')

    # Verify the payment was created in Kill Bill
    @plugin.kb_apis.proxied_services[:payment_api].payments.size.should == 1
    @plugin.kb_apis.proxied_services[:payment_api].get_payment(kb_payment_id).transactions.first.external_key.should == payment_external_key

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, [], @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :PURCHASE
    payment_infos[0].amount.should be_nil
    payment_infos[0].currency.should be_nil
    payment_infos[0].status.should == :PENDING
    payment_infos[0].gateway_error.should == '{"payment_plugin_status":"PENDING"}'
    payment_infos[0].gateway_error_code.should be_nil

    validate_token(form)

    properties = []
    properties << build_property('token', token)
    purchase_and_refund(kb_payment_id, payment_external_key, properties)

    # Verify no extra payment was created in Kill Bill by the plugin
    @plugin.kb_apis.proxied_services[:payment_api].payments.size.should == 1
  end

  private

  def validate_form(form)
    form.kb_account_id.should == @pm.kb_account_id
    form.form_url.should start_with('https://www.sandbox.paypal.com/cgi-bin/webscr')
  end

  def validate_nil_form_property(form, key)
    key_properties = form.properties.select { |prop| prop.key == key }
    key_properties.size.should == 0
  end

  def validate_form_property(form, key, value=nil)
    key_properties = form.properties.select { |prop| prop.key == key }
    key_properties.size.should == 1
    key = key_properties.first.value
    value.nil? ? key.should_not(be_nil) : key.should == value
    key
  end

  def validate_token(form)
    print "\nPlease go to #{form.form_url} to proceed and press any key to continue...
Note: you need to log-in with a paypal sandbox account (create one here: https://developer.paypal.com/webapps/developer/applications/accounts)\n"
    $stdin.gets
  end

  def purchase_and_refund(kb_payment_id, purchase_payment_external_key, purchase_properties)
    # Trigger the purchase
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment_id, purchase_payment_external_key, @pm.kb_payment_method_id, @amount, @currency, purchase_properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :PURCHASE

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, [], @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :PURCHASE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil

    # Try a full refund
    refund_response = @plugin.refund_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, [], @call_context)
    refund_response.status.should eq(:PROCESSED), refund_response.gateway_error
    refund_response.amount.should == @amount
    refund_response.transaction_type.should == :REFUND

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, [], @call_context)
    payment_infos.size.should == 2
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :PURCHASE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil
    payment_infos[1].kb_payment_id.should.should == kb_payment_id
    payment_infos[1].transaction_type.should == :REFUND
    payment_infos[1].amount.should == @amount
    payment_infos[1].currency.should == @currency
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil
  end
end
