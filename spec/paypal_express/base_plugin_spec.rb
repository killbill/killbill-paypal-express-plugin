require 'spec_helper'

describe Killbill::PaypalExpress::PaymentPlugin do

  include ::Killbill::Plugin::ActiveMerchant::RSpec

  before(:each) do
    Dir.mktmpdir do |dir|
      file = File.new(File.join(dir, 'paypal_express.yml'), 'w+')
      file.write(<<-eos)
:paypal_express:
  :signature: 'signature'
  :login: 'login'
  :password: 'password'
  :test: true
# As defined by spec_helper.rb
:database:
  :adapter: 'sqlite3'
  :database: 'test.db'
      eos
      file.close

      @plugin = build_plugin(::Killbill::PaypalExpress::PaymentPlugin, 'paypal_express', File.dirname(file))

      # Start the plugin here - since the config file will be deleted
      @plugin.start_plugin
    end
  end

  it 'should start and stop correctly' do
    @plugin.stop_plugin
  end

  it 'should receive notifications correctly' do
    description    = 'description'

    kb_tenant_id = SecureRandom.uuid
    context      = @plugin.kb_apis.create_context(kb_tenant_id)
    properties   = @plugin.hash_to_properties({ :description => description })

    notification    = ''
    gw_notification = @plugin.process_notification notification, properties, context
  end
end
