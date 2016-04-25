module BuildPluginHelpers
  def build_start_paypal_plugin(account_id = nil)
    if account_id.nil?
      plugin = build_plugin(::Killbill::PaypalExpress::PaymentPlugin, 'paypal_express')
      start_plugin plugin
    else
      account_line = "  - :account_id: #{account_id}"
      Dir.mktmpdir do |dir|
        file = File.new(File.join(dir, 'paypal_express.yml'), 'w+')
        open('paypal_express.yml', 'r') do |origin_file|
          line_num = 0
          origin_file.each_line do |line|
            file.puts(account_line) if line_num == 1
            file.puts(line)
            line_num += 1
          end
        end
        file.close
        plugin = build_plugin(::Killbill::PaypalExpress::PaymentPlugin, 'paypal_express', File.dirname(file))
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
