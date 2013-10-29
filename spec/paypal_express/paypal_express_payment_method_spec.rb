require 'spec_helper'

describe Killbill::PaypalExpress::PaypalExpressPaymentMethod do
  before :all do
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.delete_all
  end

  it 'should ignore in search results payment methods without a kb payment method id' do
    kb_account_id = SecureRandom.uuid
    token = SecureRandom.uuid
    pm1 = Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => kb_account_id,
                                                                     :kb_payment_method_id => SecureRandom.uuid,
                                                                     :paypal_express_payer_id => SecureRandom.uuid,
                                                                     :paypal_express_baid => SecureRandom.uuid,
                                                                     :paypal_express_token => token
    # Token, but not baid/kb payment method id
    pm2 = Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => kb_account_id,
                                                                     :paypal_express_token => token

    do_search(token).size.should == 1
  end

  it 'should generate the right SQL query' do
    # Check count query
    expected_query = "SELECT COUNT(DISTINCT \"paypal_express_payment_methods\".\"id\") FROM \"paypal_express_payment_methods\" LEFT OUTER JOIN \"paypal_express_responses\" ON \"paypal_express_responses\".\"api_call\" = 'details_for' AND \"paypal_express_responses\".\"success\" = 't' AND \"paypal_express_responses\".\"token\" = \"paypal_express_payment_methods\".\"paypal_express_token\" WHERE ((((\"paypal_express_payment_methods\".\"paypal_express_payer_id\" = 'XXX' OR \"paypal_express_payment_methods\".\"paypal_express_baid\" = 'XXX') OR \"paypal_express_payment_methods\".\"paypal_express_token\" = 'XXX') OR \"paypal_express_responses\".\"payer_email\" = 'XXX') OR \"paypal_express_responses\".\"payer_name\" LIKE '%XXX%') AND \"paypal_express_payment_methods\".\"kb_payment_method_id\" IS NOT NULL ORDER BY \"paypal_express_payment_methods\".\"id\""
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search_query('XXX').to_sql.should == expected_query

    # Check query with results
    expected_query = "SELECT  DISTINCT \"paypal_express_payment_methods\".* FROM \"paypal_express_payment_methods\" LEFT OUTER JOIN \"paypal_express_responses\" ON \"paypal_express_responses\".\"api_call\" = 'details_for' AND \"paypal_express_responses\".\"success\" = 't' AND \"paypal_express_responses\".\"token\" = \"paypal_express_payment_methods\".\"paypal_express_token\" WHERE ((((\"paypal_express_payment_methods\".\"paypal_express_payer_id\" = 'XXX' OR \"paypal_express_payment_methods\".\"paypal_express_baid\" = 'XXX') OR \"paypal_express_payment_methods\".\"paypal_express_token\" = 'XXX') OR \"paypal_express_responses\".\"payer_email\" = 'XXX') OR \"paypal_express_responses\".\"payer_name\" LIKE '%XXX%') AND \"paypal_express_payment_methods\".\"kb_payment_method_id\" IS NOT NULL ORDER BY \"paypal_express_payment_methods\".\"id\" LIMIT 10 OFFSET 0"
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.search_query('XXX', 0, 10).to_sql.should == expected_query
  end

  it 'should search all fields' do
    do_search('foo').size.should == 0

    pm = Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => '11-22-33-44',
                                                                    :kb_payment_method_id => '55-66-77-88',
                                                                    :paypal_express_payer_id => 38102343,
                                                                    :paypal_express_baid => 'baid',
                                                                    :paypal_express_token => 'token'

    do_search('foo').size.should == 0
    do_search(pm.paypal_express_payer_id).size.should == 1
    do_search('baid').size.should == 1
    do_search('token').size.should == 1
    # No partial match for payer id
    do_search(2343).size.should == 0

    pm2 = Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => '22-33-44-55',
                                                                     :kb_payment_method_id => '66-77-88-99',
                                                                     :paypal_express_payer_id => 49384029302,
                                                                     :paypal_express_baid => 'baid',
                                                                     :paypal_express_token => 'token'

    do_search('foo').size.should == 0
    do_search(pm.paypal_express_payer_id).size.should == 1
    do_search(pm2.paypal_express_payer_id).size.should == 1
    do_search('baid').size.should == 2
    do_search('token').size.should == 2
    # No partial match for payer id
    do_search(2343).size.should == 0

    # New pm with new token
    pm3 = Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => '66-77-88-99',
                                                                     :kb_payment_method_id => '08-09-10-11',
                                                                     :paypal_express_payer_id => 9938420,
                                                                     :paypal_express_baid => 'baid2',
                                                                     :paypal_express_token => 'token2'
    # Check search by name
    do_search('good').size.should == 0
    do_search('bad').size.should == 0
    # Check partial search
    do_search('goo').size.should == 0
    do_search('ba').size.should == 0
    # Check search by email
    do_search('visible@visible.com').size.should == 0
    do_search('hidden@visible.com').size.should == 0

    # Good response
    Killbill::PaypalExpress::PaypalExpressResponse.create :api_call => 'details_for',
                                                          :token => 'token2',
                                                          :success => true,
                                                          :payer_name => 'good',
                                                          :payer_email => 'visible@visible.com'
    # Create a dup, to make sure we see it only once
    Killbill::PaypalExpress::PaypalExpressResponse.create :api_call => 'details_for',
                                                          :token => 'token2',
                                                          :success => true,
                                                          :payer_name => 'good',
                                                          :payer_email => 'visible@visible.com'
    # Bad response: wrong api call
    Killbill::PaypalExpress::PaypalExpressResponse.create :api_call => 'something',
                                                          :token => 'token2',
                                                          :success => true,
                                                          :payer_name => 'bad',
                                                          :payer_email => 'hidden@hidden.com'
    # Bad response: wrong token
    Killbill::PaypalExpress::PaypalExpressResponse.create :api_call => 'details_for',
                                                          :token => 'something',
                                                          :success => true,
                                                          :payer_name => 'bad',
                                                          :payer_email => 'hidden@hidden.com'
    # Bad response: not successful
    Killbill::PaypalExpress::PaypalExpressResponse.create :api_call => 'details_for',
                                                          :token => 'token2',
                                                          :success => false,
                                                          :payer_name => 'bad',
                                                          :payer_email => 'hidden@hidden.com'

    # Check search by name
    do_search('good').size.should == 1
    do_search('bad').size.should == 0
    # Check partial search
    do_search('goo').size.should == 1
    do_search('ba').size.should == 0
    # Check search by email
    do_search('visible@visible.com').size.should == 1
    do_search('hidden@visible.com').size.should == 0
  end

  private

  def do_search(search_key)
    pagination = Killbill::PaypalExpress::PaypalExpressPaymentMethod.search(search_key)
    pagination.current_offset.should == 0
    results = pagination.iterator.to_a
    pagination.total_nb_records.should == results.size
    results
  end
end
