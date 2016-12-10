# -- encoding : utf-8 --

set :views, File.expand_path(File.dirname(__FILE__) + '/views')

include Killbill::Plugin::ActiveMerchant::Sinatra

configure do
  # Usage: rackup -Ilib -E test
  if development? or test?
    # Make sure the plugin is initialized
    plugin              = ::Killbill::PaypalExpress::PaymentPlugin.new
    plugin.logger       = Logger.new(STDOUT)
    plugin.logger.level = Logger::INFO
    plugin.conf_dir     = File.dirname(File.dirname(__FILE__)) + '/..'
    plugin.start_plugin
  end
end

helpers do
  def plugin(session = {})
    ::Killbill::PaypalExpress::PrivatePaymentPlugin.new(session)
  end
end

# curl -v http://127.0.0.1:9292/plugins/killbill-paypal-express/form
get '/plugins/killbill-paypal-express/form', :provides => 'html' do
  order_id   = request.GET['order_id']
  account_id = request.GET['account_id']
  options    = {
      :amount           => request.GET['amount'],
      :currency         => request.GET['currency'],
      :test             => request.GET['test'],
      :credential2      => request.GET['credential2'],
      :credential3      => request.GET['credential3'],
      :credential4      => request.GET['credential4'],
      :country          => request.GET['country'],
      :account_name     => request.GET['account_name'],
      :transaction_type => request.GET['transaction_type'],
      :authcode         => request.GET['authcode'],
      :notify_url       => request.GET['notify_url'],
      :return_url       => request.GET['return_url'],
      :redirect_param   => request.GET['redirect_param'],
      :forward_url      => request.GET['forward_url']
  }

  @form = plugin(session).payment_form_for(order_id, account_id, :paypal, options) do |service|
    # Add your custom hidden tags here, e.g.
    #service.token = config[:paypal-express][:token]
    submit_tag 'Submit'
  end

  erb :form
end

# curl -v -XPOST http://127.0.0.1:9292/plugins/killbill-paypal-express/1.0/setup-checkout --data-binary '{"kb_account_id":"a6b33ba1"}'
post '/plugins/killbill-paypal-express/1.0/setup-checkout', :provides => 'json' do
  begin
    data = JSON.parse request.body.read
  rescue JSON::ParserError => e
    halt 400, {'Content-Type' => 'text/plain'}, "Invalid payload: #{e}"
  end

  kb_tenant_id = data['kb_tenant_id'] || request.env['killbill_tenant'].id.to_s
  options = (data['options'] || {}).deep_symbolize_keys

  response = plugin.initiate_express_checkout data['kb_account_id'],
                                              kb_tenant_id,
                                              data['amount_in_cents'] || 0,
                                              data['currency'] || 'USD',
                                              true,
                                              options
  unless response.success?
    status 500
    response.message
  else
    redirect plugin.to_express_checkout_url(response, kb_tenant_id, options)
  end
end

# curl -v http://127.0.0.1:9292/plugins/killbill-paypal-express/1.0/pms/1
get '/plugins/killbill-paypal-express/1.0/pms/:id', :provides => 'json' do
  if pm = ::Killbill::PaypalExpress::PaypalExpressPaymentMethod.find_by_id(params[:id].to_i)
    pm.to_json
  else
    status 404
  end
end

# curl -v http://127.0.0.1:9292/plugins/killbill-paypal-express/1.0/transactions/1
get '/plugins/killbill-paypal-express/1.0/transactions/:id', :provides => 'json' do
  if transaction = ::Killbill::PaypalExpress::PaypalExpressTransaction.find_by_id(params[:id].to_i)
    transaction.to_json
  else
    status 404
  end
end

# curl -v http://127.0.0.1:9292/plugins/killbill-paypal-express/1.0/responses/1
get '/plugins/killbill-paypal-express/1.0/responses/:id', :provides => 'json' do
  if transaction = ::Killbill::PaypalExpress::PaypalExpressResponse.find_by_id(params[:id].to_i)
    transaction.to_json
  else
    status 404
  end
end

# curl -v http://127.0.0.1:9292/plugins/killbill-paypal-express/1.0/accounts/somebody@example.com
get '/plugins/killbill-paypal-express/1.0/accounts/:email', :provides => 'json' do
  if ids = ::Killbill::PaypalExpress::PaypalExpressResponse.uniq.where(:payer_email => params[:email]).pluck(:kb_account_id)
    ids.to_json
  else
    status 404
  end
end

# curl -v http://127.0.0.1:9292/plugins/killbill-paypal-express/1.0/payer_emails/41d95965-8213-4434-ac04-0f7dbe51988c
get '/plugins/killbill-paypal-express/1.0/payer_emails/:kb_account_id', :provides => 'json' do
  if emails = ::Killbill::PaypalExpress::PaypalExpressResponse.uniq.where(:kb_account_id => params[:kb_account_id]).where("payer_email IS NOT NULL").pluck(:payer_email)
    emails.to_json
  else
    status 404
  end
end
