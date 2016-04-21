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
    verify_payment_method
  end

  before(:each) do
    ::Killbill::PaypalExpress::PaypalExpressTransaction.delete_all
    ::Killbill::PaypalExpress::PaypalExpressResponse.delete_all
    # clean the payments before each spec to avoid one influences each other
    @plugin.kb_apis.proxied_services[:payment_api].delete_all_payments
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
      payment_infos[0].gateway_error.should == '{"payment_plugin_status":"PENDING"}'
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
    payment_processor_account_id = 'paypal_test_account'
    1.upto(n) do |i|
      payment_external_key = SecureRandom.uuid
      is_pending_payment_test = i % 2 == 1 ? false : true
      properties = @plugin.hash_to_properties(
          :transaction_external_key => payment_external_key,
          # test both with and without pending payments
          :create_pending_payment => is_pending_payment_test,
          :payment_processor_account_id => payment_processor_account_id,
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
        payment_infos[0].gateway_error.should == '{"payment_plugin_status":"PENDING"}'
        payment_infos[0].gateway_error_code.should be_nil
        find_value_from_properties(payment_infos[0].properties, :payment_processor_account_id).should == payment_processor_account_id
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
      authorize_capture_and_refund(kb_payment_id, payment_external_key, properties, payment_processor_account_id)

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
    payment_processor_account_id = 'paypal_test_account'
    1.upto(n) do |i|
      payment_external_key = SecureRandom.uuid
      is_pending_payment_test = i % 2 == 1 ? false : true
      properties = @plugin.hash_to_properties(
          :transaction_external_key => payment_external_key,
          :create_pending_payment => is_pending_payment_test,
          :auth_mode => true,
          :payment_processor_account_id => payment_processor_account_id
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

      authorize_and_void(kb_payment_id, payment_external_key, properties, payment_processor_account_id)

      # Verify no extra payment was created in Kill Bill by the plugin
      @plugin.kb_apis.proxied_services[:payment_api].payments.size.should == i / 2
    end

    # Each loop triggers one successful authorize and one successful void
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

    payment_processor_account_id = 'paypal_test_account'

    properties = @plugin.hash_to_properties(
        :transaction_external_key => SecureRandom.uuid,
        :create_pending_payment => true,
        :auth_mode => true,
        :payment_processor_account_id => payment_processor_account_id
    )
    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    token = validate_form_property(form, 'token')
    @plugin.send(:find_payment_processor_id_from_initial_call, @pm.kb_account_id, @call_context.tenant_id, token).should == payment_processor_account_id

    properties = @plugin.hash_to_properties(
        :transaction_external_key => SecureRandom.uuid,
        :auth_mode => true,
        :payment_processor_account_id => payment_processor_account_id
    )
    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    token = validate_form_property(form, 'token')
    @plugin.send(:find_payment_processor_id_from_initial_call, @pm.kb_account_id, @call_context.tenant_id, token).should == payment_processor_account_id

    properties = @plugin.hash_to_properties(
        :transaction_external_key => SecureRandom.uuid,
        :create_pending_payment => true,
        :payment_processor_account_id => payment_processor_account_id
    )
    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    token = validate_form_property(form, 'token')
    @plugin.send(:find_payment_processor_id_from_initial_call, @pm.kb_account_id, @call_context.tenant_id, token).should == payment_processor_account_id

    properties = @plugin.hash_to_properties(
        :transaction_external_key => SecureRandom.uuid,
        :payment_processor_account_id => payment_processor_account_id
    )
    form = @plugin.build_form_descriptor(@pm.kb_account_id, @form_fields, properties, @call_context)
    token = validate_form_property(form, 'token')
    @plugin.send(:find_payment_processor_id_from_initial_call, @pm.kb_account_id, @call_context.tenant_id, token).should == payment_processor_account_id
  end

  private

  def validate_form(form)
    form.kb_account_id.should == @pm.kb_account_id
    form.form_url.should start_with('https://www.sandbox.paypal.com/cgi-bin/webscr')
    form.form_method.should == 'GET'
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

  def authorize_capture_and_refund(kb_payment_id, payment_external_key, properties, payment_processor_account_id)
    # Trigger the authorize
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, kb_payment_id, payment_external_key, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :AUTHORIZE

    # Verify GET AUTHORIZED PAYMENT
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[0].properties, 'paymentInfoPaymentStatus').should == 'Pending'
    find_value_from_properties(payment_infos[0].properties, 'paymentInfoPendingReason').should == 'authorization'
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == payment_processor_account_id

    # Trigger the capture
    payment_response = @plugin.capture_payment(@pm.kb_account_id, kb_payment_id, payment_external_key, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :CAPTURE

    # Verify GET CAPTURED PAYMENT
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    # Two expected transactions: one auth and one capture
    payment_infos.size.should == 2
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == payment_processor_account_id
    payment_infos[1].kb_payment_id.should == kb_payment_id
    payment_infos[1].transaction_type.should == :CAPTURE
    payment_infos[1].amount.should == @amount
    payment_infos[1].currency.should == @currency
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[1].properties, 'paymentInfoPaymentStatus').should == 'Completed'
    find_value_from_properties(payment_infos[1].properties, 'payment_processor_account_id').should == payment_processor_account_id

    # Try a full refund
    refund_response = @plugin.refund_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, [], @call_context)
    refund_response.status.should eq(:PROCESSED), refund_response.gateway_error
    refund_response.amount.should == @amount
    refund_response.transaction_type.should == :REFUND

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    payment_infos.size.should == 3
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == payment_processor_account_id
    payment_infos[1].kb_payment_id.should == kb_payment_id
    payment_infos[1].transaction_type.should == :CAPTURE
    payment_infos[1].amount.should == @amount
    payment_infos[1].currency.should == @currency
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[1].properties, 'payment_processor_account_id').should == payment_processor_account_id
    payment_infos[2].kb_payment_id.should.should == kb_payment_id
    payment_infos[2].transaction_type.should == :REFUND
    payment_infos[2].amount.should == @amount
    payment_infos[2].currency.should == @currency
    payment_infos[2].status.should == :PROCESSED
    payment_infos[2].gateway_error.should == 'Success'
    payment_infos[2].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[2].properties, 'payment_processor_account_id').should == payment_processor_account_id
  end

  def authorize_and_double_capture(kb_payment_id, payment_external_key, properties)
    # Trigger the authorize
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, kb_payment_id, payment_external_key, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :AUTHORIZE

    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil

    # Trigger the capture
    payment_response = @plugin.capture_payment(@pm.kb_account_id, kb_payment_id, payment_external_key, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :CAPTURE

    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    payment_infos.size.should == 2
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil
    payment_infos[1].kb_payment_id.should == kb_payment_id
    payment_infos[1].transaction_type.should == :CAPTURE
    payment_infos[1].amount.should == @amount
    payment_infos[1].currency.should == @currency
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil

    # Trigger a capture again with full amount
    payment_response = @plugin.capture_payment(@pm.kb_account_id, kb_payment_id, payment_external_key, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    payment_response.status.should eq(:ERROR), payment_response.gateway_error
    payment_response.amount.should == nil
    payment_response.transaction_type.should == :CAPTURE

    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    payment_infos.size.should == 3
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil
    payment_infos[1].kb_payment_id.should == kb_payment_id
    payment_infos[1].transaction_type.should == :CAPTURE
    payment_infos[1].amount.should == @amount
    payment_infos[1].currency.should == @currency
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil
    payment_infos[2].kb_payment_id.should.should == kb_payment_id
    payment_infos[2].transaction_type.should == :CAPTURE
    payment_infos[2].amount.should be_nil
    payment_infos[2].currency.should be_nil
    payment_infos[2].status.should == :ERROR
    payment_infos[2].gateway_error.should == 'Authorization has already been completed.'
    payment_infos[2].gateway_error_code.should be_nil
  end

  def authorize_and_void(kb_payment_id, payment_external_key, properties, payment_processor_account_id)
    # Trigger the authorize
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, kb_payment_id, payment_external_key, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.amount.should == @amount
    payment_response.transaction_type.should == :AUTHORIZE

    # Verify get_payment_info
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == payment_processor_account_id

    # Trigger the void
    payment_response = @plugin.void_payment(@pm.kb_account_id, kb_payment_id, payment_external_key, @pm.kb_payment_method_id, properties, @call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
    payment_response.transaction_type.should == :VOID

    # Verify get_payment_info
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, properties, @call_context)
    # Two expected transactions: one auth and one capture
    payment_infos.size.should == 2
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should == @amount
    payment_infos[0].currency.should == @currency
    payment_infos[0].status.should == :PROCESSED
    payment_infos[0].gateway_error.should == 'Success'
    payment_infos[0].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[0].properties, 'payment_processor_account_id').should == payment_processor_account_id
    payment_infos[1].kb_payment_id.should == kb_payment_id
    payment_infos[1].transaction_type.should == :VOID
    payment_infos[1].status.should == :PROCESSED
    payment_infos[1].gateway_error.should == 'Success'
    payment_infos[1].gateway_error_code.should be_nil
    find_value_from_properties(payment_infos[1].properties, 'payment_processor_account_id').should == payment_processor_account_id
  end

  def purchase_with_missing_token
    failed_purchase([], :CANCELED, 'Could not find the payer_id: the token is missing', 'RuntimeError')
  end

  def authorize_with_missing_token
    failed_authorize([], :CANCELED, 'Could not find the payer_id: the token is missing', 'RuntimeError')
  end

  def purchase_with_invalid_token(purchase_properties)
    failed_purchase(purchase_properties, :CANCELED, "Could not find the payer_id for token #{properties_to_hash(purchase_properties)[:token]}", 'RuntimeError')
  end

  def authorize_with_invalid_token(authorize_properties)
    failed_authorize(authorize_properties, :CANCELED, "Could not find the payer_id for token #{properties_to_hash(authorize_properties)[:token]}", 'RuntimeError')
  end

  def subsequent_purchase(purchase_properties)
    failed_purchase(purchase_properties, :ERROR, 'A successful transaction has already been completed for this token.')
  end

  def failed_authorize(authorize_properties, status, msg, gateway_error_code=nil)
    kb_payment_id = SecureRandom.uuid

    payment_response = @plugin.authorize_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, authorize_properties, @call_context)
    payment_response.status.should eq(status), payment_response.gateway_error
    payment_response.amount.should be_nil
    payment_response.transaction_type.should == :AUTHORIZE

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, [], @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :AUTHORIZE
    payment_infos[0].amount.should be_nil
    payment_infos[0].currency.should be_nil
    payment_infos[0].status.should == status
    payment_infos[0].gateway_error.should == msg
    payment_infos[0].gateway_error_code.should == gateway_error_code
  end

  def failed_purchase(purchase_properties, status, msg, gateway_error_code=nil)
    kb_payment_id = SecureRandom.uuid

    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, purchase_properties, @call_context)
    payment_response.status.should eq(status), payment_response.gateway_error
    payment_response.amount.should be_nil
    payment_response.transaction_type.should == :PURCHASE

    # Verify GET API
    payment_infos = @plugin.get_payment_info(@pm.kb_account_id, kb_payment_id, [], @call_context)
    payment_infos.size.should == 1
    payment_infos[0].kb_payment_id.should == kb_payment_id
    payment_infos[0].transaction_type.should == :PURCHASE
    payment_infos[0].amount.should be_nil
    payment_infos[0].currency.should be_nil
    payment_infos[0].status.should == status
    payment_infos[0].gateway_error.should == msg
    payment_infos[0].gateway_error_code.should == gateway_error_code
  end

  def verify_payment_method
    # Verify our table directly
    payment_methods = ::Killbill::PaypalExpress::PaypalExpressPaymentMethod.from_kb_account_id(@pm.kb_account_id, @call_context.tenant_id)
    payment_methods.size.should == 1
    payment_method = payment_methods.first
    payment_method.should_not be_nil
    payment_method.paypal_express_payer_id.should be_nil
    payment_method.token.should be_nil
    payment_method.kb_payment_method_id.should == @pm.kb_payment_method_id
  end
end
