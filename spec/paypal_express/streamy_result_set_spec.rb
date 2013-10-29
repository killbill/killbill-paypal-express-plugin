require 'spec_helper'

describe Killbill::PaypalExpress::StreamyResultSet do
  before :all do
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.delete_all
  end

  it 'should stream results per batch' do
    1.upto(35) do
      Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => SecureRandom.uuid,
                                                                 :kb_payment_method_id => SecureRandom.uuid,
                                                                 :paypal_express_payer_id => SecureRandom.uuid,
                                                                 :paypal_express_baid => SecureRandom.uuid,
                                                                 :paypal_express_token => SecureRandom.uuid
    end
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.count.should == 35

    enum = Killbill::PaypalExpress::StreamyResultSet.new(40, 10) do |offset,limit|
      Killbill::PaypalExpress::PaypalExpressPaymentMethod.where('kb_payment_method_id is not NULL')
                                                         .order("id ASC")
                                                         .offset(offset)
                                                         .limit(limit)
    end

    i = 0
    enum.each do |results|
      if i < 3
        results.size.should == 10
      elsif i == 3
        results.size.should == 5
      else
        fail 'Too many results'
      end
      i += 1
    end
  end
end
