require 'spec_helper'
require 'logger'
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
    @plugin.root = File.dirname(file)
    @plugin.config_file_name = File.basename(file)
    @plugin.logger = Logger.new(STDOUT)
  end

  it "should start and stop correctly" do
    @plugin.start_plugin
    @plugin.stop_plugin
  end
end
