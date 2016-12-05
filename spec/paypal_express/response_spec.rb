require 'spec_helper'
require 'nokogiri'

describe Killbill::PaypalExpress::PaypalExpressResponse do

  def load_paypal_response(action, suffix)
    @spec_root ||= File.expand_path(File.join(File.dirname(__FILE__), ".."))
    xml = IO.read(File.join(@spec_root, "fixtures", action + "-" + suffix + ".xml"))
    ActiveMerchant::Billing::PaypalGateway.any_instance.stub(:build_request).and_return(nil)
    ActiveMerchant::Billing::PaypalGateway.any_instance.stub(:ssl_post).and_return(xml)
    api = ActiveMerchant::Billing::PaypalGateway.new(:login => "dummy", :password => "password", :signature => "dummy")
    api.send(:commit, action, nil)
  end

  it 'should read a successful GetExpressCheckoutDetails response correctly' do
    action = "GetExpressCheckoutDetails"
    response = ::Killbill::PaypalExpress::PaypalExpressResponse.from_response(
      action,         # api_call
      "account1",     # kb_account_id
      "payment1",     # kb_payment_id
      nil,            # kb_payment_transaction_id
      nil,            # transaction_type
      "account2",     # payment_processor_account_id
      "tenant1",      # kb_tenant_id
      load_paypal_response(action, "success")
    )
    expect(response.api_call).to eq(action)
    expect(response.kb_account_id).to eq("account1")
    expect(response.kb_payment_id).to eq("payment1")
    expect(response.kb_payment_transaction_id).to be_nil
    expect(response.transaction_type).to be_nil
    expect(response.payment_processor_account_id).to eq("account2")
    expect(response.kb_tenant_id).to eq("tenant1")
    # data from the fixture as parsed by PaypalCommonAPI and PaypalExpressResponse
    expect(response.message).to eq("Success")
    expect(response.authorization).to be_nil
    expect(response.fraud_review).to eq(false)
    expect(response.success).to eq(true)

    expect(response.token).to eq("EC-MY_TOKEN")
    expect(response.payer_id).to eq("MY_PAYER_ID")
    expect(response.payment_info_reasoncode).to be_nil

    expect(response.gateway_error_code).to be_nil
  end

  it 'should read a DoExpressCheckoutPayment response with an error code correctly' do
    action = "DoExpressCheckoutPayment"
    response = ::Killbill::PaypalExpress::PaypalExpressResponse.from_response(
      action,         # api_call
      "account1",     # kb_account_id
      "payment1",     # kb_payment_id
      "transaction1", # kb_payment_transaction_id
      :purchase,      # transaction_type
      "account2",     # payment_processor_account_id
      "tenant1",      # kb_tenant_id
      load_paypal_response(action, "duplicate")
    )
    expect(response.api_call).to eq(action)
    expect(response.kb_account_id).to eq("account1")
    expect(response.kb_payment_id).to eq("payment1")
    expect(response.kb_payment_transaction_id).to eq("transaction1")
    expect(response.transaction_type).to eq(:purchase)
    expect(response.payment_processor_account_id).to eq("account2")
    expect(response.kb_tenant_id).to eq("tenant1")
    # data from the fixture as parsed by PaypalCommonAPI and PaypalExpressResponse
    expect(response.message).to eq("A successful transaction has already been completed for this token.")
    expect(response.authorization).to eq("3K289148GS508731G")
    expect(response.fraud_review).to eq(false)
    expect(response.success).to eq(false)

    expect(response.token).to eq("EC-MY_TOKEN")
    expect(response.payer_id).to be_nil
    expect(response.payment_info_reasoncode).to eq("11607")

    expect(response.gateway_error_code).to eq("11607")
  end

end
