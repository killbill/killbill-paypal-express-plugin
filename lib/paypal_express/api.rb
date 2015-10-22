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
        @private_api = ::Killbill::PaypalExpress::PrivatePaymentPlugin.new
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
        if find_value_from_properties(properties, 'from_hpp') == 'true'
          options[:token] = find_value_from_properties(properties, 'token')

          response = @response_model.create(:api_call                     => :build_form_descriptor,
                                            :kb_account_id                => kb_account_id,
                                            :kb_payment_id                => kb_payment_id,
                                            :kb_payment_transaction_id    => kb_payment_transaction_id,
                                            :transaction_type             => :PURCHASE,
                                            :authorization                => options[:token],
                                            :payment_processor_account_id => nil,
                                            :kb_tenant_id                 => context.tenant_id,
                                            :success                      => true,
                                            :created_at                   => Time.now.utc,
                                            :updated_at                   => Time.now.utc,
                                            :message                      => response_message = {
                                                                               :exception_class => "",
                                                                               :exception_message => "",
                                                                               :payment_plugin_status => :PENDING
                                                                             }.to_json)
          transaction        = response.to_transaction_info_plugin(nil)
          transaction.status = :PENDING
          transaction
        else
          add_required_options(kb_payment_transaction_id, kb_payment_method_id, context, options)

          # if we have a baid on file then it will be in the options now
          if options[:token]
            gateway_call_proc = Proc.new do |gateway, linked_transaction, payment_source, amount_in_cents, options|
              # Can't use default implementation: the purchase signature is for one-off payments only
              gateway.reference_transaction(amount_in_cents, options)
            end
          else
            options[:token]    = find_value_from_properties(properties, 'token')
            options[:payer_id] = find_value_from_properties(properties, 'payer_id')
            gateway_call_proc  = Proc.new do |gateway, linked_transaction, payment_source, amount_in_cents, options|
              gateway.purchase(amount_in_cents, options)
            end
          end
          unless options[:payer_id]
            options[:payer_id] = find_payer_api(options[:token],
                                                kb_account_id,
                                                context.tenant_id,
                                                properties_to_hash(properties))
          end
          properties = merge_properties(properties, options)
          dispatch_to_gateways(:purchase, kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context, gateway_call_proc)
        end
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
        linked_transaction_type = @transaction_model.purchases_from_kb_payment_id(kb_payment_id, context.tenant_id).size > 0 ? :PURCHASE : :CAPTURE

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

        if token.nil?
          # HPP flow
          options = {
              :skip_gw => true
          }
        else
          # Go to Paypal to get the Payer id (GetExpressCheckoutDetails call)
          payer_id = find_payer_api(token, kb_account_id, context.tenant_id, properties_to_hash(properties))
          options  = {
              :paypal_express_token    => token,
              :paypal_express_payer_id => payer_id
          }
        end

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
        descriptor_fields = merge_properties(descriptor_fields, options)
        form_fields       = properties_to_hash(descriptor_fields)
        kb_account        = @kb_apis.account_user_api.get_account_by_id(kb_account_id, context)
        kb_payment_method = (@kb_apis.payment_api.get_account_payment_methods(kb_account_id, false, [], context).find { |pm| pm.plugin_name == 'killbill-paypal-express' })
        payment_methods   = @payment_method_model.from_kb_account_id(kb_account_id, context.tenant_id)
        token             = payment_method.paypal_express_token unless payment_methods.empty?
        amount            = (form_fields[:amount] || "0").to_i
        currency          = form_fields[:currency] || kb_account.currency

        unless token
          response = @private_api.initiate_express_checkout(kb_account_id,
                                                            context.tenant_id.to_s,
                                                            amount,
                                                            currency,
                                                            false,
                                                            form_fields)
          unless response.success?
            raise "Unable to initiate paypal express checkout: #{response.message}"
          end
          token = response.token
        end

        properties_hash       = properties_to_hash(properties)
        should_create_payment = Killbill::Plugin::ActiveMerchant::Utils.normalized(form_fields, :create_pending_payment)

        if should_create_payment
          custom_props         = hash_to_properties(:from_hpp => true,
                                                    :token    => token)
          payment_external_key = form_fields[:payment_external_key]

          payment = @kb_apis.payment_api
                            .create_purchase(kb_account,
                                             kb_payment_method.id,
                                             nil,
                                             amount,
                                             currency,
                                             payment_external_key,
                                             token,
                                             custom_props,
                                             context)
          properties << build_property('kb_payment_id', payment.id)
        end
        descriptor          = super(kb_account_id, descriptor_fields, properties, context)
        descriptor.form_url = @private_api.to_express_checkout_url(response, context.tenant_id, options)
        descriptor
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

      def to_express_checkout_url(response, kb_tenant_id, options = {})
        payment_processor_account_id = options[:payment_processor_account_id] || :default
        gateway                      = lookup_gateway(payment_processor_account_id, kb_tenant_id)
        gateway.redirect_url_for(response.token)
      end

      protected

      def get_active_merchant_module
        ::OffsitePayments.integration(:paypal)
      end

      private

      def find_payer_api(token, kb_account_id, kb_tenant_id, options = {})
        # Go to Paypal to get the Payer id (GetExpressCheckoutDetails call)
        payment_processor_account_id = options[:payment_processor_account_id] || :default
        gateway                      = lookup_gateway(payment_processor_account_id, kb_tenant_id)
        gw_response                  = gateway.details_for(token)
        response, transaction        = save_response_and_transaction(gw_response, :details_for, kb_account_id, kb_tenant_id, payment_processor_account_id)

        raise response.message unless response.success?
        raise "Could not find the payer_id for token #{token}" if response.payer_id.blank?

        response.payer_id
      end

      def add_required_options(kb_payment_transaction_id, kb_payment_method_id, context, options)
        payment_method = @payment_method_model.from_kb_payment_method_id(kb_payment_method_id, context.tenant_id)

        options[:payer_id]     ||= payment_method.paypal_express_payer_id.presence
        options[:token]        ||= payment_method.paypal_express_token.presence
        options[:reference_id] ||= payment_method.token.presence # baid

        options[:payment_type] ||= 'Any'
        options[:invoice_id]   ||= kb_payment_transaction_id
        options[:ip]           ||= @ip
      end
    end
  end
end
