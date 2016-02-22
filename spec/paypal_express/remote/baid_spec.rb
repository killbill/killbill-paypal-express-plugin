require 'spec_helper'

ActiveMerchant::Billing::Base.mode = :test

describe Killbill::PaypalExpress::PaymentPlugin do

  include ::Killbill::Plugin::ActiveMerchant::RSpec

  # Share the BAID
  before(:all) do
    @plugin = build_plugin(::Killbill::PaypalExpress::PaymentPlugin, 'paypal_express')
    svcs = @plugin.kb_apis.proxied_services
    svcs[:payment_api] = PaypalExpressJavaPaymentApi.new(@plugin)
    @plugin.kb_apis = ::Killbill::Plugin::KillbillApi.new('paypal_express', svcs)
    @plugin.start_plugin

    @call_context = build_call_context

    @properties = []
    @amount = BigDecimal.new('100')
    @currency = 'USD'

    kb_account_id = SecureRandom.uuid
    external_key, kb_account_id = create_kb_account(kb_account_id, @plugin.kb_apis.proxied_services[:account_user_api])

    # Initiate the setup process
    response = create_token(kb_account_id, @call_context.tenant_id)
    token = response.token
    print "\nPlease go to #{@plugin.to_express_checkout_url(response, @call_context.tenant_id)} to proceed and press any key to continue...
Note: you need to log-in with a paypal sandbox account (create one here: https://developer.paypal.com/webapps/developer/applications/accounts)\n"
    $stdin.gets

    # Complete the setup process
    @properties << build_property('token', token)
    @pm = create_payment_method(::Killbill::PaypalExpress::PaypalExpressPaymentMethod, kb_account_id, @call_context.tenant_id, @properties)

    # Verify our table directly. Note that @pm.token is the baid
    payment_methods = ::Killbill::PaypalExpress::PaypalExpressPaymentMethod.from_kb_account_id_and_token(@pm.token, kb_account_id, @call_context.tenant_id)
    payment_methods.size.should == 1
    payment_method = payment_methods.first
    payment_method.should_not be_nil
    payment_method.paypal_express_payer_id.should_not be_nil
    payment_method.token.should == @pm.token
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

  it 'should be able to charge and refund' do
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :PURCHASE

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == @kb_payment.id
    payment_infos[0].transaction_type.should == :PURCHASE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil

    # Try a full refund
    refund_response = @plugin.refund_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[1].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    refund_response.status.should eq(:PROCESSED), refund_response.gateway_error
    refund_response.amount.should == @amount
    refund_response.transaction_type.should == :REFUND

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
    payment_infos.size.should == 2
    payment_infos[0].kb_payment_id.should == @kb_payment.id
    payment_infos[0].transaction_type.should == :PURCHASE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil
    payment_infos[1].kb_payment_id.should == @kb_payment.id
    payment_infos[1].transaction_type.should == :REFUND
    payment_infos[1].amount.should == @amount
    payment_infos[1].currency.should == @currency
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil
  end

  it 'should be able to auth, capture and refund' do
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :AUTHORIZE

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == @kb_payment.id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil

    # Try multiple partial captures
    partial_capture_amount = BigDecimal.new('10')
    1.upto(3) do |i|
      payment_response = @plugin.capture_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[i].id, @pm.kb_payment_method_id, partial_capture_amount, @currency, @properties, @call_context)
      payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
      payment_response.amount.should == partial_capture_amount
      payment_response.transaction_type.should == :CAPTURE

      # Verify GET API
      payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
      payment_infos.size.should == 1 + i
      payment_infos[i].kb_payment_id.should == @kb_payment.id
      payment_infos[i].transaction_type.should == :CAPTURE
      payment_infos[i].amount.should == partial_capture_amount
      payment_infos[i].currency.should == @currency
      payment_infos[i].status.should == :PROCESSED
      payment_infos[i].gateway_error.should == 'Success'
      payment_infos[i].gateway_error_code.should be_nil
    end

    # Try a partial refund
    refund_response = @plugin.refund_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[4].id, @pm.kb_payment_method_id, partial_capture_amount, @currency, @properties, @call_context)
    refund_response.status.should eq(:PROCESSED), refund_response.gateway_error
    refund_response.amount.should == partial_capture_amount
    refund_response.transaction_type.should == :REFUND

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
    payment_infos.size.should == 5
    payment_infos[4].kb_payment_id.should == @kb_payment.id
    payment_infos[4].transaction_type.should == :REFUND
    payment_infos[4].amount.should == partial_capture_amount
    payment_infos[4].currency.should == @currency
    payment_infos[4].status.should == :PROCESSED
    payment_infos[4].gateway_error.should == 'Success'
    payment_infos[4].gateway_error_code.should be_nil

    # Try to capture again
    payment_response = @plugin.capture_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[5].id, @pm.kb_payment_method_id, partial_capture_amount, @currency, @properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == partial_capture_amount
    payment_response.transaction_type.should == :CAPTURE

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
    payment_infos.size.should == 6
    payment_infos[5].kb_payment_id.should == @kb_payment.id
    payment_infos[5].transaction_type.should == :CAPTURE
    payment_infos[5].amount.should == partial_capture_amount
    payment_infos[5].currency.should == @currency
    payment_infos[5].status.should == :PROCESSED
    payment_infos[5].gateway_error.should == 'Success'
    payment_infos[5].gateway_error_code.should be_nil
  end

  it 'should be able to auth and void' do
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :AUTHORIZE

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == @kb_payment.id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil

    payment_response = @plugin.void_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[1].id, @pm.kb_payment_method_id, @properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.transaction_type.should == :VOID

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
    payment_infos.size.should == 2
    payment_infos[0].kb_payment_id.should == @kb_payment.id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil
    payment_infos[1].kb_payment_id.should == @kb_payment.id
    payment_infos[1].transaction_type.should == :VOID
    payment_infos[1].amount.should be_nil
    payment_infos[1].currency.should be_nil
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil
  end

  it 'should be able to auth, partial capture and void' do
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :AUTHORIZE

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == @kb_payment.id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil

    partial_capture_amount = BigDecimal.new('10')
    payment_response = @plugin.capture_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[1].id, @pm.kb_payment_method_id, partial_capture_amount, @currency, @properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == partial_capture_amount
    payment_response.transaction_type.should == :CAPTURE

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
    payment_infos.size.should == 2
    payment_infos[1].kb_payment_id.should == @kb_payment.id
    payment_infos[1].transaction_type.should == :CAPTURE
    payment_infos[1].amount.should == partial_capture_amount
    payment_infos[1].currency.should == @currency
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil

    payment_response = @plugin.void_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[2].id, @pm.kb_payment_method_id, @properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.transaction_type.should == :VOID

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, [], @call_context)
    payment_infos.size.should == 3
    payment_infos[2].kb_payment_id.should == @kb_payment.id
    payment_infos[2].transaction_type.should == :VOID
    payment_infos[2].amount.should be_nil
    payment_infos[2].currency.should be_nil
    payment_infos[2].status.should == :PROCESSED
    payment_infos[2].gateway_error.should == 'Success'
    payment_infos[2].gateway_error_code.should be_nil
  end

  it 'should generate forms correctly' do
    context = @plugin.kb_apis.create_context(@call_context.tenant_id)
    fields  = @plugin.hash_to_properties(
                 :order_id => '1234',
                 :amount   => 12,
              )

    properties = @plugin.hash_to_properties(
      :create_pending_payment => false
    )

    form = @plugin.build_form_descriptor(@pm.kb_account_id, fields, properties, context)

    form.kb_account_id.should == @pm.kb_account_id
    form.form_method.should   == 'POST'
    form.form_url.should start_with('https://www.sandbox.paypal.com/cgi-bin/webscr')
  end

  private

  def create_token(kb_account_id, kb_tenant_id)
    private_plugin = ::Killbill::PaypalExpress::PrivatePaymentPlugin.new
    response       = private_plugin.initiate_express_checkout(kb_account_id, kb_tenant_id)
    response.success.should be_true
    response
  end
end
