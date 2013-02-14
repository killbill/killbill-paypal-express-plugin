require 'active_merchant'
require 'json'
require 'sinatra'

require 'paypal_express/gateway'

def gateway
  gateway = PaypalExpress::Gateway.instance

  if development? or test?
    # Find credentials in environment variables:
    #   export PAYPAL_SIGNATURE='XXXYYY'
    #   export PAYPAL_LOGIN='xxx.example.com'
    #   export PAYPAL_PASSWORD='XXXYYY'
    #
    # Usage: ruby web.rb -e [ENVIRONMENT]
    gateway.configure({
                        :signature => ENV['PAYPAL_SIGNATURE'],
                        :login     => ENV['PAYPAL_LOGIN'],
                        :password  => ENV['PAYPAL_PASSWORD'],
                      })
  end
end

post '/plugins/killbill-paypal-express/1.0/auth', :provides => 'json' do
  begin
    data = JSON.parse request.body.read
  rescue JSON::ParserError
    halt 400, {'Content-Type' => 'text/plain'}, 'Invalid payload'
  end

  res = gateway.setup_authorization data['dollars'] || 1,
                                    :return_url => data['return_url'] || 'http://www.example.com/success',
                                    :cancel_return_url => data['cancel_return_url'] || 'http://www.example.com/failure',
                                    :billing_agreement => { :type => 'MerchantInitiatedBilling', :description => 'Agreement Description', :payment_type => '' }
  if res.success?
    status 200
    res.token
  else
    status 500
    res.inspect
  end
end

run Sinatra::Application
