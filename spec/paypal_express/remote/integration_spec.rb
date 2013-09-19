require 'spec_helper'
require 'logger'

ActiveMerchant::Billing::Base.mode = :test

describe Killbill::PaypalExpress::PaymentPlugin do
  before(:each) do
    @plugin = Killbill::PaypalExpress::PaymentPlugin.new
    @plugin.conf_dir = File.expand_path(File.dirname(__FILE__) + '../../../../')

    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    @plugin.logger = logger

    @plugin.start_plugin

    @pm = create_payment_method
  end

  after(:each) do
    @plugin.stop_plugin
  end

  it 'should be able to charge and refund' do
    amount = BigDecimal.new("100")
    currency = 'USD'
    kb_payment_id = SecureRandom.uuid

    payment_response = @plugin.process_payment @pm.kb_account_id, kb_payment_id, @pm.kb_payment_method_id, amount, currency
    payment_response.amount.should == amount
    payment_response.status.should == :PROCESSED

    # Verify our table directly
    response = Killbill::PaypalExpress::PaypalExpressResponse.find_by_api_call_and_kb_payment_id :charge, kb_payment_id
    response.test.should be_true
    response.success.should be_true
    response.message.should == 'Success'

    # Check we can retrieve the payment
    payment_response = @plugin.get_payment_info @pm.kb_account_id, kb_payment_id
    payment_response.first_payment_reference_id.should_not be_nil
    payment_response.amount.should == amount
    payment_response.status.should == :PROCESSED

    # Check we cannot refund an amount greater than the original charge
    lambda { @plugin.process_refund @pm.kb_account_id, kb_payment_id, amount + 1, currency }.should raise_error RuntimeError

    refund_response = @plugin.process_refund @pm.kb_account_id, kb_payment_id, amount, currency
    refund_response.amount.should == amount
    refund_response.status.should == :PROCESSED

    # Verify our table directly
    response = Killbill::PaypalExpress::PaypalExpressResponse.find_by_api_call_and_kb_payment_id :refund, kb_payment_id
    response.test.should be_true
    response.success.should be_true

    # Check we can retrieve the refund
    refund_response = @plugin.get_refund_info @pm.kb_account_id, kb_payment_id
    refund_response.amount.should == amount
    refund_response.status.should == :PROCESSED

    # Try another payment to verify the BAID
    second_amount = BigDecimal.new("94.23")
    second_kb_payment_id = SecureRandom.uuid
    payment_response = @plugin.process_payment @pm.kb_account_id, second_kb_payment_id, @pm.kb_payment_method_id, second_amount, currency
    payment_response.amount.should == second_amount
    payment_response.status.should == :PROCESSED

    # Check we can refund it as well
    refund_response = @plugin.process_refund @pm.kb_account_id, second_kb_payment_id, second_amount, currency
    refund_response.amount.should == second_amount
    refund_response.status.should == :PROCESSED

    # it "should be able to create and retrieve payment methods"
    # This should be in a separate scenario but since it's so hard to create a payment method (need manual intervention),
    # we can't easily delete it
    pms = @plugin.get_payment_methods @pm.kb_account_id, false
    pms.size.should == 1
    pms[0].external_payment_method_id.should == @pm.paypal_express_baid

    pm_details = @plugin.get_payment_method_detail(@pm.kb_account_id, @pm.kb_payment_method_id)
    pm_details.external_payment_method_id.should == @pm.paypal_express_baid

    pms_found = @plugin.search_payment_methods @pm.paypal_express_baid
    pms_found.size.should == 1
    pms_found.first.external_payment_method_id.should == pm_details.external_payment_method_id

    @plugin.delete_payment_method @pm.kb_account_id, @pm.kb_payment_method_id

    @plugin.get_payment_methods(@pm.kb_account_id, false).size.should == 0
    lambda { @plugin.get_payment_method_detail(@pm.kb_account_id, @pm.kb_payment_method_id) }.should raise_error RuntimeError
  end

  private

  def create_payment_method
    kb_account_id = SecureRandom.uuid
    private_plugin = Killbill::PaypalExpress::PrivatePaymentPlugin.instance

    # Initiate the setup process
    response = private_plugin.initiate_express_checkout kb_account_id
    response.success.should be_true
    token = response.token

    print "\nPlease go to #{response.to_express_checkout_url} to proceed and press any key to continue...
Note: you need to log-in with a paypal sandbox account (create one here: https://developer.paypal.com/webapps/developer/applications/accounts)\n"
    $stdin.gets

    # Complete the setup process
    kb_payment_method_id = SecureRandom.uuid
    pm_kv_info = Killbill::Plugin::Model::PaymentMethodKVInfo.new
    pm_kv_info.key = 'token'
    pm_kv_info.value = token
    info = Killbill::Plugin::Model::PaymentMethodPlugin.new
    info.properties = [pm_kv_info]
    response = @plugin.add_payment_method kb_account_id, kb_payment_method_id, info, true
    response.should be_true

    # Verify our table directly
    payment_method = Killbill::PaypalExpress::PaypalExpressPaymentMethod.from_kb_account_id_and_token(kb_account_id, token)
    payment_method.should_not be_nil
    payment_method.paypal_express_payer_id.should_not be_nil
    payment_method.paypal_express_baid.should_not be_nil
    payment_method.kb_payment_method_id.should == kb_payment_method_id

    payment_method
  end
end
