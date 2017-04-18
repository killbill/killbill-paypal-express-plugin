require 'spec_helper'
require_relative 'hpp_spec_helpers'
require_relative 'build_plugin_helpers'

ActiveMerchant::Billing::Base.mode = :test

shared_examples 'hpp_spec_common' do

  before(:each) do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.delete_all
    ::Killbill::PaypalExpress::PaypalExpressResponse.delete_all
    # clean the payments before each spec to avoid one influences each other
    @plugin.kb_apis.proxied_services[:payment_api].delete_all_payments
  end

  it 'should return an empty list of plugin info if payment does not exist' do
    payment_plugin_info = @plugin.get_payment_info(@pm.kb_account_id, SecureRandom.uuid, [], @call_context)
    payment_plugin_info.size.should == 0
  end

  it 'should generate forms correctly' do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 0
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 0

    # Verify the payment cannot go through without the token
    purchase_with_missing_token

    # Verify multiple payments can be triggered for the same payment method
    n = 2
    1.upto(n) do
      form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, [], @call_context)
      validate_form(form)
      validate_nil_form_property(form, 'kb_payment_id')
      validate_nil_form_property(form, 'kb_transaction_external_key')
      token = validate_form_property(form, 'token')

      # Verify no payment was created in Kill Bill
      @plugin.kb_apis.proxied_services[:payment_api].payments.should be_empty

      properties = []
      properties << build_property('token', token)

      # Verify the payment cannot go through until the token is validated
      purchase_with_invalid_token(properties)

      validate_token(form)

      purchase_and_refund(SecureRandom.uuid, SecureRandom.uuid, properties)

      # Verify no extra payment was created in Kill Bill by the plugin
      @plugin.kb_apis.proxied_services[:payment_api].payments.should be_empty

      # Verify the token cannot be re-used
      subsequent_purchase(properties)

      # Verify no token/baid was stored
      verify_payment_method
    end

    # Each loop triggers one successful purchase and one successful refund
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 2 * n
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 1 + 8 * n
  end

  it 'should generate forms with pending payments correctly' do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 0
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 0

    # Verify the payment cannot go through without the token
    purchase_with_missing_token

    # Verify multiple payments can be triggered for the same payment method
    n = 2
    1.upto(n) do |i|
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
      @plugin.kb_apis.proxied_services[:payment_api].payments.size.should == i
      @plugin.kb_apis.proxied_services[:payment_api].get_payment(kb_payment_id).transactions.first.external_key.should == payment_external_key

      # Verify GET API
      payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, [], @call_context)
      payment_infos.size.should == 1
      payment_infos[0].kb_payment_id.should == kb_payment_id
      payment_infos[0].transaction_type.should == :PURCHASE
      payment_infos[0].amount.should be_nil
      payment_infos[0].currency.should be_nil
      payment_infos[0].status.should == :PENDING
      payment_infos[0].gateway_error.should == {:payment_plugin_status => 'PENDING',
                                                :token_expiration_period => @plugin.class.const_get(:THREE_HOURS_AGO).to_s}.to_json
      payment_infos[0].gateway_error_code.should be_nil

      properties = []
      properties << build_property('token', token)

      # Verify the payment cannot go through until the token is validated
      purchase_with_invalid_token(properties)

      validate_token(form)

      purchase_and_refund(kb_payment_id, payment_external_key, properties)

      # Verify no extra payment was created in Kill Bill by the plugin
      @plugin.kb_apis.proxied_services[:payment_api].payments.size.should == i

      # Verify the token cannot be re-used
      subsequent_purchase(properties)

      # Verify no token/baid was stored
      verify_payment_method
    end

    # Each loop triggers one successful purchase and one successful refund
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 2 * n
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 1 + 9 * n
  end

  it 'should generate forms and perform auth, capture and refund correctly' do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 0
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 0

    # Verify the authorization cannot go through without the token
    authorize_with_missing_token

    # Verify multiple payments can be triggered for the same payment method
    n = 2
    1.upto(n) do |i|
      payment_external_key = SecureRandom.uuid
      is_pending_payment_test = i % 2 == 1 ? false : true
      properties = @plugin.hash_to_properties(
          :transaction_external_key => payment_external_key,
          # test both with and without pending payments
          :create_pending_payment => is_pending_payment_test,
          :payment_processor_account_id => @payment_processor_account_id,
          :auth_mode => true
      )
      form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
      validate_form(form)
      token = validate_form_property(form, 'token')
      # Verify payments were created when create_pending_payment is true
      @plugin.kb_apis.proxied_services[:payment_api].payments.size.should == i / 2
      if is_pending_payment_test
        kb_payment_id = validate_form_property(form, 'kb_payment_id')
        validate_form_property(form, 'kb_transaction_external_key', payment_external_key)
        @plugin.kb_apis.proxied_services[:payment_api].get_payment(kb_payment_id).transactions.first.external_key.should == payment_external_key
        # Verify GET API
        payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
        payment_infos.size.should == 1
        payment_infos[0].kb_payment_id.should == kb_payment_id
        payment_infos[0].transaction_type.should == :AUTHORIZE
        payment_infos[0].amount.should be_nil
        payment_infos[0].currency.should be_nil
        payment_infos[0].status.should == :PENDING
        payment_infos[0].gateway_error.should == {:payment_plugin_status => 'PENDING',
                                                  :token_expiration_period => @plugin.class.const_get(:THREE_HOURS_AGO).to_s}.to_json
        payment_infos[0].gateway_error_code.should be_nil
        find_value_from_properties(payment_infos[0].properties, :payment_processor_account_id).should == @payment_processor_account_id
      else
        kb_payment_id = SecureRandom.uuid
        validate_nil_form_property(form, 'kb_payment_id')
        validate_nil_form_property(form, 'kb_transaction_external_key')
      end

      properties = []
      properties << build_property(:token, token)
      # Verify the payment cannot be authorized without the token being validated
      authorize_with_invalid_token(properties)
      # Go to PayPal to validate the token
      validate_token(form)

      # Verify auth, capture and refund
      authorize_capture_and_refund(kb_payment_id, payment_external_key, properties, @payment_processor_account_id)

      # Verify no extra payment was created in Kill Bill by the plugin
      @plugin.kb_apis.proxied_services[:payment_api].payments.size.should == (i / 2)

      # Verify no token/baid was stored
      verify_payment_method
    end

    # Each loop triggers one successful auth, one successful capture and one successful refund
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 3 * n
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 1 + 15 * n / 2 + 7 * n % 2
  end

  it 'should perform auth and void correctly' do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 0
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 0

    # Verify multiple payments can be triggered for the same payment method
    n = 2
    1.upto(n) do |i|
      payment_external_key = SecureRandom.uuid
      is_pending_payment_test = i % 2 == 1 ? false : true
      properties = @plugin.hash_to_properties(
          :transaction_external_key => payment_external_key,
          :create_pending_payment => is_pending_payment_test,
          :auth_mode => true,
          :payment_processor_account_id => @payment_processor_account_id
      )
      form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
      validate_form(form)
      token = validate_form_property(form, 'token')
      if is_pending_payment_test
        kb_payment_id = validate_form_property(form, 'kb_payment_id')
      else
        kb_payment_id = SecureRandom.uuid
      end

      # Go to PayPal to validate the token
      validate_token(form)

      properties = []
      properties << build_property('token', token)

      authorize_and_void(kb_payment_id, payment_external_key, properties, @payment_processor_account_id)

      # Verify no extra payment was created in Kill Bill by the plugin
      @plugin.kb_apis.proxied_services[:payment_api].payments.size.should == i / 2
    end

    # Each loop triggers one successful authorize and void
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 2 * n
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 9 * n / 2 + 5 * n % 2
  end

  it 'should not capture the same transaction twice with full amount' do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 0
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 0

    payment_external_key = SecureRandom.uuid
    properties = @plugin.hash_to_properties(
        :transaction_external_key => payment_external_key,
        :create_pending_payment => true,
        :auth_mode => true
    )

    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    validate_form(form)
    kb_payment_id = validate_form_property(form, 'kb_payment_id')
    validate_form_property(form, 'kb_transaction_external_key', payment_external_key)
    token = validate_form_property(form, 'token')

    properties = []
    properties << build_property('token', token)
    properties << build_property('auth_mode', 'true')

    validate_token(form)

    authorize_and_double_capture(kb_payment_id, payment_external_key, properties)
  end

  it 'should find the payment processor id from the initial_express_call' do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 0
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 0

    properties = @plugin.hash_to_properties(
        :transaction_external_key => SecureRandom.uuid,
        :create_pending_payment => true,
        :auth_mode => true,
        :payment_processor_account_id => @payment_processor_account_id
    )
    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    token = validate_form_property(form, 'token')
    @plugin.send(:find_payment_processor_id_from_initial_call, @pm.kb_account_id, @call_context.tenant_id, token).should == @payment_processor_account_id

    properties = @plugin.hash_to_properties(
        :transaction_external_key => SecureRandom.uuid,
        :auth_mode => true,
        :payment_processor_account_id => @payment_processor_account_id
    )
    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    token = validate_form_property(form, 'token')
    @plugin.send(:find_payment_processor_id_from_initial_call, @pm.kb_account_id, @call_context.tenant_id, token).should == @payment_processor_account_id

    properties = @plugin.hash_to_properties(
        :transaction_external_key => SecureRandom.uuid,
        :create_pending_payment => true,
        :payment_processor_account_id => @payment_processor_account_id
    )
    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    token = validate_form_property(form, 'token')
    @plugin.send(:find_payment_processor_id_from_initial_call, @pm.kb_account_id, @call_context.tenant_id, token).should == @payment_processor_account_id

    properties = @plugin.hash_to_properties(
        :transaction_external_key => SecureRandom.uuid,
        :payment_processor_account_id => @payment_processor_account_id
    )
    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    token = validate_form_property(form, 'token')
    @plugin.send(:find_payment_processor_id_from_initial_call, @pm.kb_account_id, @call_context.tenant_id, token).should == @payment_processor_account_id
  end

  it 'should cancel the pending payment if the token expires' do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 0
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 0

    expiration_period = 5
    payment_external_key = SecureRandom.uuid
    properties = @plugin.hash_to_properties(
        :transaction_external_key => payment_external_key,
        :create_pending_payment => true,
        :token_expiration_period => expiration_period
    )

    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    kb_payment_id = validate_form_property(form, 'kb_payment_id')
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].amount.should be_nil
    payment_infos[0].currency.should be_nil
    payment_infos[0].status.should == :PENDING
    payment_infos[0].gateway_error.should == {:payment_plugin_status => 'PENDING',
                                              :token_expiration_period => expiration_period.to_s}.to_json
    payment_infos[0].gateway_error_code.should be_nil

    sleep payment_infos[0].created_date + expiration_period - Time.parse(@plugin.clock.get_clock.get_utc_now.to_s) + 1

    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    # Make sure no extra response is created
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].amount.should be_nil
    payment_infos[0].currency.should be_nil
    payment_infos[0].status.should == :CANCELED
    payment_infos[0].gateway_error.should == 'Token expired. Payment Canceled by Janitor.'
    payment_infos[0].gateway_error_code.should be_nil
  end

  it 'should cancel the pending payment if the token expires without passing property' do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.count.should == 0
    ::Killbill::PaypalExpress::PaypalExpressResponse.count.should == 0

    expiration_period = 5
    @plugin.class.const_set(:THREE_HOURS_AGO, expiration_period)
    payment_external_key = SecureRandom.uuid
    properties = @plugin.hash_to_properties(
        :transaction_external_key => payment_external_key,
        :create_pending_payment => true
    )

    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    kb_payment_id = validate_form_property(form, 'kb_payment_id')
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].amount.should be_nil
    payment_infos[0].currency.should be_nil
    payment_infos[0].status.should == :PENDING
    payment_infos[0].gateway_error.should == {:payment_plugin_status => 'PENDING',
                                              :token_expiration_period => expiration_period.to_s}.to_json
    payment_infos[0].gateway_error_code.should be_nil

    sleep payment_infos[0].created_date + expiration_period - Time.parse(@plugin.clock.get_clock.get_utc_now.to_s) + 1

    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    # Make sure no extra response is created
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].amount.should be_nil
    payment_infos[0].currency.should be_nil
    payment_infos[0].status.should == :CANCELED
    payment_infos[0].gateway_error.should == 'Token expired. Payment Canceled by Janitor.'
    payment_infos[0].gateway_error_code.should be_nil
  end

  it 'should fix the unknown transactions to success' do
    [:AUTHORIZE, :CAPTURE, :REFUND].each do |type|
      payment_external_key = SecureRandom.uuid
      properties = @plugin.hash_to_properties(
          :transaction_external_key => payment_external_key,
          :create_pending_payment => true,
          :payment_processor_account_id => @payment_processor_account_id,
          :auth_mode => true
      )
      form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
      kb_payment_id = validate_form_property(form, 'kb_payment_id')
      kb_trx_id = validate_form_property(form, 'kb_transaction_id')
      validate_token(form)

      @plugin.authorize_payment(@pm.kb_account_id, kb_payment_id, kb_trx_id, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
      nb_plugin_info = 1
      if type == :AUTHORIZE
        verify_janitor_transition nb_plugin_info, type, :PROCESSED, kb_payment_id
        # Be able to capture
        payment_response = @plugin.capture_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
        payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
        payment_response.amount.should == @amount
        payment_response.transaction_type.should == :CAPTURE
      elsif type == :CAPTURE
        nb_plugin_info = 2
        @plugin.capture_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
        verify_janitor_transition nb_plugin_info, type, :PROCESSED, kb_payment_id
        # Be able to refund
        payment_response = @plugin.refund_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
        payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
        payment_response.amount.should == @amount
        payment_response.transaction_type.should == :REFUND
      elsif type == :REFUND
        nb_plugin_info = 3
        @plugin.capture_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
        @plugin.refund_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
        verify_janitor_transition nb_plugin_info, type, :PROCESSED, kb_payment_id
      end
    end
  end

  it 'should fix the unknown transactions to plugin failure' do
    [:AUTHORIZE, :CAPTURE, :REFUND].each do |type|
      payment_external_key = SecureRandom.uuid
      properties = @plugin.hash_to_properties(
          :transaction_external_key => payment_external_key,
          :create_pending_payment => true,
          :payment_processor_account_id => @payment_processor_account_id,
          :auth_mode => true
      )
      form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
      kb_payment_id = validate_form_property(form, 'kb_payment_id')
      kb_trx_id = validate_form_property(form, 'kb_transaction_id')
      validate_token(form)

      properties = @plugin.hash_to_properties({:skip_gw => true})
      @plugin.authorize_payment(@pm.kb_account_id, kb_payment_id, kb_trx_id, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
      nb_plugin_info = 1
      if type == :CAPTURE
        nb_plugin_info = 2
        @plugin.capture_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
      elsif type == :REFUND
        nb_plugin_info = 3
        @plugin.capture_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
        @plugin.refund_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
      end
      verify_janitor_transition nb_plugin_info, type, :CANCELED, kb_payment_id
    end
  end

  it 'should remain in unknown if cancellation period is not reached' do
    [:AUTHORIZE, :CAPTURE, :REFUND].each do |type|
      payment_external_key = SecureRandom.uuid
      properties = @plugin.hash_to_properties(
          :transaction_external_key => payment_external_key,
          :create_pending_payment => true,
          :payment_processor_account_id => @payment_processor_account_id,
          :auth_mode => true
      )
      form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
      kb_payment_id = validate_form_property(form, 'kb_payment_id')
      kb_trx_id = validate_form_property(form, 'kb_transaction_id')
      validate_token(form)

      properties = @plugin.hash_to_properties({:skip_gw => true})
      @plugin.authorize_payment(@pm.kb_account_id, kb_payment_id, kb_trx_id, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
      nb_plugin_info = 1
      if type == :CAPTURE
        nb_plugin_info = 2
        @plugin.capture_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
      elsif type == :REFUND
        nb_plugin_info = 3
        @plugin.capture_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
        @plugin.refund_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
      end
      verify_janitor_transition nb_plugin_info, type, :UNDEFINED, kb_payment_id, true, 3600*3
    end
  end
end

describe Killbill::PaypalExpress::PaymentPlugin do
  include ::Killbill::Plugin::ActiveMerchant::RSpec
  include ::Killbill::PaypalExpress::BuildPluginHelpers
  include ::Killbill::PaypalExpress::HppSpecHelpers

  context 'hpp test with a single account' do
    before(:all) do
      @payment_processor_account_id = 'default'
      @plugin = build_start_paypal_plugin
      hpp_setup
    end

    include_examples 'hpp_spec_common'
  end

  context 'hpp test with multiple accounts' do
    before(:all) do
      @payment_processor_account_id = 'paypal_test_account'
      @plugin = build_start_paypal_plugin @payment_processor_account_id
      hpp_setup
    end

    include_examples 'hpp_spec_common'
  end
end
