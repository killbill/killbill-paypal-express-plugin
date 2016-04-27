module Killbill
  module PaypalExpress
    module BuildPluginHelpers
      def build_start_paypal_plugin(account_id = nil)
        if account_id.nil?
          plugin = build_plugin(::Killbill::PaypalExpress::PaymentPlugin, 'paypal_express')
          start_plugin plugin
        else
          config = YAML.load_file('paypal_express.yml')
          existing_credential = {:account_id => account_id}.merge config[:paypal_express]
          second_credential = {:account_id => "#{account_id}_duplicate"}.merge config[:paypal_express]
          config[:paypal_express] = [second_credential, existing_credential]
          Dir.mktmpdir do |dir|
            file_name = File.join(dir, 'paypal_express.yml')
            File.open(file_name, 'w+') do |file|
              YAML.dump(config, file)
            end
            plugin = build_plugin(::Killbill::PaypalExpress::PaymentPlugin, 'paypal_express', File.dirname(file_name))
            start_plugin plugin
          end
        end
      end

      def start_plugin(plugin)
        svcs = plugin.kb_apis.proxied_services
        svcs[:payment_api] = PaypalExpressJavaPaymentApi.new(plugin)
        plugin.kb_apis = ::Killbill::Plugin::KillbillApi.new('paypal_express', svcs)
        plugin.start_plugin
        plugin
      end
    end
  end
end
