require 'spec_helper'
require_relative 'build_plugin_helpers'
require_relative 'baid_spec_helpers'

ActiveMerchant::Billing::Base.mode = :test

shared_examples 'baid_spec_common' do
  before(:each) do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.delete_all
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
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == @payment_processor_account_id

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
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == @payment_processor_account_id
    payment_infos[1].kb_payment_id.should == @kb_payment.id
    payment_infos[1].transaction_type.should == :REFUND
    payment_infos[1].amount.should == @amount
    payment_infos[1].currency.should == @currency
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[1].properties, 'payment_processor_account_id').should == @payment_processor_account_id
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
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == @payment_processor_account_id

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
      find_value_from_properties(payment_infos[i].properties, 'payment_processor_account_id').should == @payment_processor_account_id
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
    find_value_from_properties(payment_infos[4].properties, 'payment_processor_account_id').should == @payment_processor_account_id

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
    find_value_from_properties(payment_infos[5].properties, 'payment_processor_account_id').should == @payment_processor_account_id
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
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == @payment_processor_account_id

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
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == @payment_processor_account_id
    payment_infos[1].kb_payment_id.should == @kb_payment.id
    payment_infos[1].transaction_type.should == :VOID
    payment_infos[1].amount.should be_nil
    payment_infos[1].currency.should be_nil
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[1].properties, 'payment_processor_account_id').should == @payment_processor_account_id
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
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == @payment_processor_account_id

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
    find_value_from_properties(payment_infos[1].properties, 'payment_processor_account_id').should == @payment_processor_account_id

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
    find_value_from_properties(payment_infos[2].properties, 'payment_processor_account_id').should == @payment_processor_account_id
  end

  it 'should generate forms correctly' do
    context = @plugin.kb_apis.create_context(@call_context.tenant_id)
    fields = @plugin.hash_to_properties(
        :order_id => '1234',
        :amount => 12
    )

    properties = @plugin.hash_to_properties(
        :create_pending_payment => false
    )

    form = @plugin.build_form_descriptor(@pm.kb_account_id, fields, properties, context)

    form.kb_account_id.should == @pm.kb_account_id
    form.form_method.should == 'GET'
    form.form_url.should start_with('https://www.sandbox.paypal.com/cgi-bin/webscr')
  end

end

describe Killbill::PaypalExpress::PaymentPlugin do
  include ::Killbill::Plugin::ActiveMerchant::RSpec
  include ::Killbill::PaypalExpress::BuildPluginHelpers
  include ::Killbill::PaypalExpress::BaidSpecHelpers

  context 'baid test with a single account' do
    # Share the BAID
    before(:all) do
      # delete once here because we need to keep the initial response for later tests to find the payment processor account id
      ::Killbill::PaypalExpress::PaypalExpressResponse.delete_all
      @payment_processor_account_id = 'default'
      @plugin = build_start_paypal_plugin
      baid_setup
    end

    include_examples 'baid_spec_common'
  end

  context 'baid tests with multiple accounts' do
    # Share the BAID
    before(:all) do
      # delete once here because we need to keep the initial response for later tests to find the payment processor account id
      ::Killbill::PaypalExpress::PaypalExpressResponse.delete_all
      @payment_processor_account_id = 'paypal_test_account'
      @plugin = build_start_paypal_plugin @payment_processor_account_id
      baid_setup @payment_processor_account_id
    end

    include_examples 'baid_spec_common'
  end
end
