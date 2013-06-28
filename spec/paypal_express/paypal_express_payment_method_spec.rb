require 'spec_helper'

describe Killbill::PaypalExpress::PaypalExpressPaymentMethod do
  it 'should search all fields' do
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search('foo').size.should == 0

    pm = Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => '11-22-33-44',
                                                                    :kb_payment_method_id => '55-66-77-88',
                                                                    :paypal_express_payer_id => 38102343,
                                                                    :paypal_express_baid => 'baid',
                                                                    :paypal_express_token => 'token'

    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search('foo').size.should == 0
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search(pm.paypal_express_payer_id).size.should == 1
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search('baid').size.should == 1
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search('token').size.should == 1
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search(2343).size.should == 1

    pm2 = Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => '22-33-44-55',
                                                                     :kb_payment_method_id => '66-77-88-99',
                                                                     :paypal_express_payer_id => 49384029302,
                                                                     :paypal_express_baid => 'baid',
                                                                     :paypal_express_token => 'token'

    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search('foo').size.should == 0
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search(pm.paypal_express_payer_id).size.should == 1
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search(pm2.paypal_express_payer_id).size.should == 1
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search('baid').size.should == 2
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search('token').size.should == 2
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search(2343).size.should == 1
  end
end
