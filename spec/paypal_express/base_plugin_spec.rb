require 'spec_helper'

describe Killbill::PaypalExpress::PaymentPlugin do
  before(:each) do
    Dir.mktmpdir do |dir|
      file = File.new(File.join(dir, 'paypal_express.yml'), "w+")
      file.write(<<-eos)
:paypal:
  :signature: 'signature'
  :login: 'login'
  :password: 'password'
# As defined by spec_helper.rb
:database:
  :adapter: 'sqlite3'
  :database: 'test.db'
      eos
      file.close

      @plugin = Killbill::PaypalExpress::PaymentPlugin.new
      @plugin.logger = Logger.new(STDOUT)
      @plugin.conf_dir = File.dirname(file)

      # Start the plugin here - since the config file will be deleted
      @plugin.start_plugin
    end
  end

  it 'should start and stop correctly' do
    @plugin.stop_plugin
  end

  it 'should reset payment methods' do
    kb_account_id = '129384'

    @plugin.get_payment_methods(kb_account_id, false, nil).size.should == 0
    verify_pms kb_account_id, 0

    # Create a pm with a kb_payment_method_id
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => kb_account_id,
                                                               :kb_payment_method_id => 'kb-1',
                                                               :paypal_express_token => 'doesnottmatter',
                                                               :paypal_express_baid => 'paypal-1'
    verify_pms kb_account_id, 1

    # Add some in KillBill and reset
    payment_methods = []
    # Random order... Shouldn't matter...
    payment_methods << create_pm_info_plugin(kb_account_id, 'kb-3', false, 'paypal-3')
    payment_methods << create_pm_info_plugin(kb_account_id, 'kb-2', false, 'paypal-2')
    payment_methods << create_pm_info_plugin(kb_account_id, 'kb-4', false, 'paypal-4')
    @plugin.reset_payment_methods kb_account_id, payment_methods
    verify_pms kb_account_id, 4

    # Add a payment method without a kb_payment_method_id
    Killbill::PaypalExpress::PaypalExpressPaymentMethod.create :kb_account_id => kb_account_id,
                                                               :paypal_express_token => 'doesnottmatter',
                                                               :paypal_express_baid => 'paypal-5'
    @plugin.get_payment_methods(kb_account_id, false, nil).size.should == 5

    # Verify we can match it
    payment_methods << create_pm_info_plugin(kb_account_id, 'kb-5', false, 'paypal-5')
    @plugin.reset_payment_methods kb_account_id, payment_methods
    verify_pms kb_account_id, 5

    @plugin.stop_plugin
  end

  private

  def verify_pms(kb_account_id, size)
    pms = @plugin.get_payment_methods(kb_account_id, false, nil)
    pms.size.should == size
    pms.each do |pm|
      pm.account_id.should == kb_account_id
      pm.is_default.should == false
      pm.external_payment_method_id.should == 'paypal-' + pm.payment_method_id.split('-')[1]
    end
  end

  def create_pm_info_plugin(kb_account_id, kb_payment_method_id, is_default, external_payment_method_id)
    pm_info_plugin = Killbill::Plugin::Model::PaymentMethodInfoPlugin.new
    pm_info_plugin.account_id = kb_account_id
    pm_info_plugin.payment_method_id = kb_payment_method_id
    pm_info_plugin.is_default = is_default
    pm_info_plugin.external_payment_method_id = external_payment_method_id
    pm_info_plugin
  end
end
