configure do
  # Usage: rackup -Ilib -E test
  if development? or test?
    Killbill::PaypalExpress.initialize! unless Killbill::PaypalExpress.initialized
  end
end

helpers do
  def plugin
    Killbill::PaypalExpress::PrivatePaymentPlugin.instance
  end
end

after do
  # return DB connections to the Pool if required
  ActiveRecord::Base.connection.close
end

# curl -v -XPOST http://127.0.0.1:9292/plugins/killbill-paypal-express/1.0/setup-checkout --data-binary '{"kb_account_id":"a6b33ba1"}'
post '/plugins/killbill-paypal-express/1.0/setup-checkout', :provides => 'json' do
  begin
    data = JSON.parse request.body.read
  rescue JSON::ParserError => e
    halt 400, {'Content-Type' => 'text/plain'}, "Invalid payload: #{e}"
  end

  response = plugin.initiate_express_checkout data['kb_account_id'],
                                              data['amount_in_cents'] || 0,
                                              data['currency'] || 'USD',
                                              (data['options'] || {}).deep_symbolize_keys
  unless response.success?
    status 500
    response.message
  else
    redirect response.to_express_checkout_url
  end
end

# curl -v http://127.0.0.1:9292/plugins/killbill-paypal-express/1.0/pms/1
get '/plugins/killbill-paypal-express/1.0/pms/:id', :provides => 'json' do
  if pm = Killbill::PaypalExpress::PaypalExpressPaymentMethod.find_by_id(params[:id].to_i)
    pm.to_json
  else
    status 404
  end
end

# curl -v http://127.0.0.1:9292/plugins/killbill-paypal-express/1.0/transactions/1
get '/plugins/killbill-paypal-express/1.0/transactions/:id', :provides => 'json' do
  if transaction = Killbill::PaypalExpress::PaypalExpressTransaction.find_by_id(params[:id].to_i)
    transaction.to_json
  else
    status 404
  end
end
