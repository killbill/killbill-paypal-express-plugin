require 'spec_helper'
require 'logger'

describe Killbill::PaypalExpress::PaymentPlugin do
  before(:each) do
    Dir.mktmpdir do |dir|
      file = File.new(File.join(dir, 'paypal_express.yml'), "w+")
      file.write(<<-eos)
:paypal:
  :signature: 'signature'
  :login: 'login'
  :password: 'password'
:database:
  :adapter: 'sqlite3'
  :database: 'shouldntmatter.db'
eos
      file.close

      @plugin = Killbill::PaypalExpress::PaymentPlugin.new
      @plugin.root = File.dirname(file)
      @plugin.logger = Logger.new(STDOUT)

      # Start the plugin here - since the config file will be deleted
      @plugin.start_plugin
    end
  end

  it "should start and stop correctly" do
    @plugin.stop_plugin
  end
end
