require 'spec_helper'
require 'tempfile'

describe PaypalExpress::PaymentPlugin do
  before(:each) do
    file = Tempfile.new('paypal_express')
    file.write(<<-eos)
:paypal:
  :signature: 'signature'
  :login: 'login'
  :password: 'password'
eos
    file.flush

    @plugin = PaypalExpress::PaymentPlugin.new
    @plugin.config_file = file.path
  end

  it "should start and stop correctly" do
    @plugin.start_plugin
    @plugin.stop_plugin
  end
end
