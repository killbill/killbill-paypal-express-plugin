helpers do
  def plugin
    plugin = Killbill::PaypalExpress::PrivatePaymentPlugin.instance

    # Usage: rackup -Ilib -E test
    if development? or test?
      require 'logger'
      Killbill::PaypalExpress.initialize! 'paypal_express.yml', Logger.new(STDOUT) unless Killbill::PaypalExpress.initialized
    end
    plugin
  end
end

# curl -XPOST http://127.0.0.1:9292/plugins/killbill-paypal-express/1.0/setup --data-binary '{"amount_in_cents":100}' -v
post '/plugins/killbill-paypal-express/1.0/setup', :provides => 'json' do
  begin
    data = JSON.parse request.body.read
  rescue JSON::ParserError => e
    halt 400, {'Content-Type' => 'text/plain'}, "Invalid payload: #{e}"
  end

  response = plugin.initiate_express_checkout data['amount_in_cents'] || 1, (data['options'] || {})
  unless response.success?
    status 500
    response.message
  else
    redirect response.to_express_checkout_url
  end
end
