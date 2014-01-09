require 'spec_helper'

describe Killbill::PaypalExpress::PaypalExpressResponse do
  before :all do
    Killbill::PaypalExpress::PaypalExpressResponse.delete_all
  end

  it 'should generate the right SQL query' do
    # Check count query (search query numeric)
    expected_query = "SELECT COUNT(DISTINCT \"paypal_express_responses\".\"id\") FROM \"paypal_express_responses\"  WHERE ((\"paypal_express_responses\".\"authorization\" = '1234' OR \"paypal_express_responses\".\"billing_agreement_id\" = '1234') OR \"paypal_express_responses\".\"payment_info_transactionid\" = '1234') AND (\"paypal_express_responses\".\"api_call\" = 'charge' OR \"paypal_express_responses\".\"api_call\" = 'refund') AND \"paypal_express_responses\".\"success\" = 't' ORDER BY \"paypal_express_responses\".\"id\""
    # Note that Kill Bill will pass a String, even for numeric types
    Killbill::PaypalExpress::PaypalExpressResponse.search_query('1234').to_sql.should == expected_query

    # Check query with results (search query numeric)
    expected_query = "SELECT  DISTINCT \"paypal_express_responses\".* FROM \"paypal_express_responses\"  WHERE ((\"paypal_express_responses\".\"authorization\" = '1234' OR \"paypal_express_responses\".\"billing_agreement_id\" = '1234') OR \"paypal_express_responses\".\"payment_info_transactionid\" = '1234') AND (\"paypal_express_responses\".\"api_call\" = 'charge' OR \"paypal_express_responses\".\"api_call\" = 'refund') AND \"paypal_express_responses\".\"success\" = 't' ORDER BY \"paypal_express_responses\".\"id\" LIMIT 10 OFFSET 0"
    # Note that Kill Bill will pass a String, even for numeric types
    Killbill::PaypalExpress::PaypalExpressResponse.search_query('1234', 0, 10).to_sql.should == expected_query

    # Check count query (search query string)
    expected_query = "SELECT COUNT(DISTINCT \"paypal_express_responses\".\"id\") FROM \"paypal_express_responses\"  WHERE ((\"paypal_express_responses\".\"authorization\" = 'XXX' OR \"paypal_express_responses\".\"billing_agreement_id\" = 'XXX') OR \"paypal_express_responses\".\"payment_info_transactionid\" = 'XXX') AND (\"paypal_express_responses\".\"api_call\" = 'charge' OR \"paypal_express_responses\".\"api_call\" = 'refund') AND \"paypal_express_responses\".\"success\" = 't' ORDER BY \"paypal_express_responses\".\"id\""
    Killbill::PaypalExpress::PaypalExpressResponse.search_query('XXX').to_sql.should == expected_query

    # Check query with results (search query string)
    expected_query = "SELECT  DISTINCT \"paypal_express_responses\".* FROM \"paypal_express_responses\"  WHERE ((\"paypal_express_responses\".\"authorization\" = 'XXX' OR \"paypal_express_responses\".\"billing_agreement_id\" = 'XXX') OR \"paypal_express_responses\".\"payment_info_transactionid\" = 'XXX') AND (\"paypal_express_responses\".\"api_call\" = 'charge' OR \"paypal_express_responses\".\"api_call\" = 'refund') AND \"paypal_express_responses\".\"success\" = 't' ORDER BY \"paypal_express_responses\".\"id\" LIMIT 10 OFFSET 0"
    Killbill::PaypalExpress::PaypalExpressResponse.search_query('XXX', 0, 10).to_sql.should == expected_query
  end

  it 'should search all fields' do
    do_search('foo').size.should == 0

    pm = Killbill::PaypalExpress::PaypalExpressResponse.create :api_call => 'charge',
                                                               :kb_payment_id => '11-22-33-44',
                                                               :authorization => '55-66-77-88',
                                                               :billing_agreement_id => 38102343,
                                                               :payment_info_transactionid => 'order-id-1',
                                                               :success => true

    # Wrong api_call
    ignored1 = Killbill::PaypalExpress::PaypalExpressResponse.create :api_call => 'add_payment_method',
                                                                     :kb_payment_id => pm.kb_payment_id,
                                                                     :authorization => pm.authorization,
                                                                     :billing_agreement_id => pm.billing_agreement_id,
                                                                     :payment_info_transactionid => pm.payment_info_transactionid,
                                                                     :success => true

    # Not successful
    ignored2 = Killbill::PaypalExpress::PaypalExpressResponse.create :api_call => 'charge',
                                                                     :kb_payment_id => pm.kb_payment_id,
                                                                     :authorization => pm.authorization,
                                                                     :billing_agreement_id => pm.billing_agreement_id,
                                                                     :payment_info_transactionid => pm.payment_info_transactionid,
                                                                     :success => false

    do_search('foo').size.should == 0
    do_search(pm.authorization).size.should == 1
    do_search(pm.billing_agreement_id).size.should == 1
    do_search(pm.payment_info_transactionid).size.should == 1

    pm2 = Killbill::PaypalExpress::PaypalExpressResponse.create :api_call => 'refund',
                                                                :kb_payment_id => '11-22-33-44',
                                                                :authorization => '11-22-33-44',
                                                                :billing_agreement_id => pm.billing_agreement_id,
                                                                :payment_info_transactionid => 'order-id-2',
                                                                :success => true

    do_search('foo').size.should == 0
    do_search(pm.authorization).size.should == 1
    do_search(pm.billing_agreement_id).size.should == 2
    do_search(pm.payment_info_transactionid).size.should == 1
    do_search(pm2.authorization).size.should == 1
    do_search(pm2.billing_agreement_id).size.should == 2
    do_search(pm2.payment_info_transactionid).size.should == 1
  end

  private

  def do_search(search_key)
    pagination = Killbill::PaypalExpress::PaypalExpressResponse.search(search_key)
    pagination.current_offset.should == 0
    results = pagination.iterator.to_a
    pagination.total_nb_records.should == results.size
    results
  end
end
