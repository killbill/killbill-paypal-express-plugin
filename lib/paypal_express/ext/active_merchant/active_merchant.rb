module ActiveMerchant #:nodoc:
  module Billing #:nodoc:

    KB_PLUGIN_VERSION = Gem.loaded_specs['killbill-paypal-express'].version.version rescue nil

    module PaypalCommonAPI

      DUPLICATE_REQUEST_CODE = '11607'

      alias_method :original_successful?, :successful?

      # Note: this may need more thoughts when/if we want to support MsgSubID
      # See https://developer.paypal.com/docs/classic/express-checkout/integration-guide/ECRelatedAPIOps/#idempotency
      # For now, we just want to correctly handle a subsequent payment using a one-time token
      # (error "A successful transaction has already been completed for this token.")
      def successful?(response)
        response[:error_codes] == DUPLICATE_REQUEST_CODE ? false : original_successful?(response)
      end

      # Note: ActiveMerchant is missing InvoiceID in RefundTransactionReq.
      # See https://github.com/activemerchant/active_merchant/blob/v1.48.0/lib/active_merchant/billing/gateways/paypal/paypal_common_api.rb#L314
      def build_refund_request(money, identification, options)
        xml = Builder::XmlMarkup.new

        xml.tag! 'RefundTransactionReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'RefundTransactionRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'TransactionID', identification
            xml.tag! 'Amount', amount(money), 'currencyID' => (options[:currency] || currency(money)) if money.present?
            xml.tag! 'RefundType', (options[:refund_type] || (money.present? ? 'Partial' : 'Full'))
            xml.tag! 'Memo', options[:note] unless options[:note].blank?
            xml.tag! 'InvoiceID', (options[:order_id] || options[:invoice_id]) unless (options[:order_id] || options[:invoice_id]).blank?
          end
        end

        xml.target!
      end

      def commit(action, request)
        response = parse(action, ssl_post(endpoint_url, build_request(request), build_headers))

        build_response(successful?(response), message_from(response), response,
                       :test => test?,
                       :authorization => authorization_from(response),
                       :fraud_review => fraud_review?(response),
                       :avs_result => {:code => response[:avs_code]},
                       :cvv_result => response[:cvv2_code])
      end

      def build_headers
        x_r_id = x_request_id

        headers = (@options[:headers] || {}).dup
        headers['Content-Type'] ||= 'text/xml'
        headers['User-Agent'] ||= user_agent
        headers['X-Request-Id'] ||= x_r_id unless x_r_id.blank?
        headers
      end

      def user_agent
        @@ua ||= JSON.dump({
                               :bindings_version => KB_PLUGIN_VERSION,
                               :lang => 'ruby',
                               :lang_version => "#{RUBY_VERSION} p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE})",
                               :platform => RUBY_PLATFORM,
                               :publisher => 'killbill'
                           })
      end

      def x_request_id
        # See KillbillMDCInsertingServletFilter
        org::slf4j::MDC::get('req.requestId') rescue nil
      end
    end
  end
end
