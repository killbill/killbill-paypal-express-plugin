module Killbill #:nodoc:
  module PaypalExpress #:nodoc:
    class PaymentPlugin < ::Killbill::Plugin::ActiveMerchant::PaymentPlugin

      def initialize
        gateway_builder = Proc.new do |config|
          ::ActiveMerchant::Billing::PaypalExpressGateway.new :signature => config[:signature],
                                                              :login     => config[:login],
                                                              :password  => config[:password]
        end

        super(gateway_builder,
              :paypal_express,
              ::Killbill::PaypalExpress::PaypalExpressPaymentMethod,
              ::Killbill::PaypalExpress::PaypalExpressTransaction,
              ::Killbill::PaypalExpress::PaypalExpressResponse)

        @ip = ::Killbill::Plugin::ActiveMerchant::Utils.ip
      end

      def on_event(event)
        # Require to deal with per tenant configuration invalidation
        super(event)
        #
        # Custom event logic could be added below...
        #
      end

      def authorize_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        add_required_options(kb_payment_transaction_id, kb_payment_method_id, context, options)

        properties        = merge_properties(properties, options)

        # Can't use default implementation: the authorize signature is for one-off payments only
        #super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        gateway_call_proc = Proc.new do |gateway, linked_transaction, payment_source, amount_in_cents, options|
          gateway.authorize_reference_transaction(amount_in_cents, options)
        end

        dispatch_to_gateways(:authorize, kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context, gateway_call_proc)
      end

      def capture_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Pass extra parameters for the gateway here
        options = {
            # NotComplete to allow for partial captures.
            # If Complete, any remaining amount of the original authorized transaction is automatically voided and all remaining open authorizations are voided.
            :complete_type => 'NotComplete'
        }

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
      end

      def purchase_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        add_required_options(kb_payment_transaction_id, kb_payment_method_id, context, options)

        properties        = merge_properties(properties, options)

        # Can't use default implementation: the purchase signature is for one-off payments only
        #super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        gateway_call_proc = Proc.new do |gateway, linked_transaction, payment_source, amount_in_cents, options|
          gateway.reference_transaction(amount_in_cents, options)
        end

        dispatch_to_gateways(:purchase, kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context, gateway_call_proc)
      end

      def void_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, properties, context)
        # Pass extra parameters for the gateway here
        options = {
            # Void the original authorization
            :linked_transaction_type => :authorize
        }

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, properties, context)
      end

      def credit_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
      end

      def refund_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Cannot refund based on authorizations (default behavior)
        linked_transaction_type = @transaction_model.purchases_from_kb_payment_id(kb_payment_id, context.tenant_id).size > 0 ? :purchase : :capture

        # Pass extra parameters for the gateway here
        options                 = {
            :linked_transaction_type => linked_transaction_type
        }

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
      end

      def get_payment_info(kb_account_id, kb_payment_id, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, properties, context)
      end

      def search_payments(search_key, offset, limit, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(search_key, offset, limit, properties, context)
      end

      def add_payment_method(kb_account_id, kb_payment_method_id, payment_method_props, set_default, properties, context)
        # token is passed via properties
        token = find_value_from_properties(properties, 'token')
        # token is passed from the json body
        token = find_value_from_properties(payment_method_props.properties, 'token') if token.nil?
        return false if token.nil?

        # Go to Paypal to get the Payer id (GetExpressCheckoutDetails call)
        options                      = properties_to_hash(properties)
        payment_processor_account_id = options[:payment_processor_account_id] || :default
        gateway                      = lookup_gateway(payment_processor_account_id)
        gw_response                  = gateway.details_for(token)
        response, transaction        = save_response_and_transaction(gw_response, :details_for, kb_account_id, context.tenant_id, payment_processor_account_id)
        return false unless response.success? and !response.payer_id.blank?

        # Pass extra parameters for the gateway here
        options = {
            :paypal_express_token    => token,
            :paypal_express_payer_id => response.payer_id
        }

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_method_id, payment_method_props, set_default, properties, context)
      end

      def delete_payment_method(kb_account_id, kb_payment_method_id, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_method_id, properties, context)
      end

      def get_payment_method_detail(kb_account_id, kb_payment_method_id, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_method_id, properties, context)
      end

      def set_default_payment_method(kb_account_id, kb_payment_method_id, properties, context)
        # TODO
      end

      def get_payment_methods(kb_account_id, refresh_from_gateway, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(kb_account_id, refresh_from_gateway, properties, context)
      end

      def search_payment_methods(search_key, offset, limit, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(search_key, offset, limit, properties, context)
      end

      def reset_payment_methods(kb_account_id, payment_methods, properties, context)
        super
      end

      def build_form_descriptor(kb_account_id, descriptor_fields, properties, context)
        # Pass extra parameters for the gateway here
        options           = {}
        properties        = merge_properties(properties, options)

        # Add your custom static hidden tags here
        options           = {
            #:token => config[:paypal-express][:token]
        }
        descriptor_fields = merge_properties(descriptor_fields, options)

        super(kb_account_id, descriptor_fields, properties, context)
      end

      def process_notification(notification, properties, context)
        # Pass extra parameters for the gateway here
        options    = {}
        properties = merge_properties(properties, options)

        super(notification, properties, context) do |gw_notification, service|
          # Retrieve the payment
          # gw_notification.kb_payment_id =
          #
          # Set the response body
          # gw_notification.entity =
        end
      end

      def to_express_checkout_url(response, options = {})
        payment_processor_account_id = options[:payment_processor_account_id] || :default
        gateway                      = lookup_gateway(payment_processor_account_id)
        gateway.redirect_url_for(response.token)
      end

      protected

      def get_active_merchant_module
        ::OffsitePayments.integration(:paypal)
      end

      private

      def add_required_options(kb_payment_transaction_id, kb_payment_method_id, context, options)
        payment_method = @payment_method_model.from_kb_payment_method_id(kb_payment_method_id, context.tenant_id)

        options[:payer_id]     ||= payment_method.paypal_express_payer_id
        options[:token]        ||= payment_method.paypal_express_token
        options[:reference_id] ||= payment_method.token # baid

        options[:payment_type] ||= 'Any'
        options[:invoice_id]   ||= kb_payment_transaction_id
        options[:ip]           ||= @ip
      end
    end
  end
end
