module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
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
    end
  end
end
