module Killbill #:nodoc:
  module PaypalExpress #:nodoc:
    class PaymentPlugin < ::Killbill::Plugin::ActiveMerchant::PaymentPlugin

      THREE_HOURS_AGO = (3*3600)

      def initialize
        gateway_builder = Proc.new do |config|
          ::ActiveMerchant::Billing::PaypalExpressGateway.application_id = config[:button_source] || 'killbill_SP'
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
        authorize_or_purchase_payment kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context, true
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
        # by default, this call will purchase a payment
        authorize_or_purchase_payment kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context
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
        options = {
            :linked_transaction_type => linked_transaction_type
        }

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
      end

      def get_payment_info(kb_account_id, kb_payment_id, properties, context)
        t_info_plugins = super(kb_account_id, kb_payment_id, properties, context)
        # Should never happen...
        return [] if t_info_plugins.nil?

        # Completed purchases/authorizations will have two rows in the responses table (one for api_call 'build_form_descriptor', one for api_call 'purchase/authorize')
        # Other transaction types don't support the :PENDING state
        target_transaction_types = [:PURCHASE, :AUTHORIZE]
        only_pending_transaction = t_info_plugins.find { |t_info_plugin| target_transaction_types.include?(t_info_plugin.transaction_type) && t_info_plugin.status != :PENDING }.nil?
        t_info_plugins_without_pending = t_info_plugins.reject { |t_info_plugin| target_transaction_types.include?(t_info_plugin.transaction_type) && t_info_plugin.status == :PENDING }

        # If its token has expired, cancel the payment and update the response row.
        if only_pending_transaction
          return t_info_plugins unless token_expired(t_info_plugins.last)
          begin
            cancel_pending_transaction(t_info_plugins.last).nil?
            logger.info("Cancel pending kb_payment_id='#{t_info_plugins.last.kb_payment_id}', kb_payment_transaction_id='#{t_info_plugins.last.kb_transaction_payment_id}'")
            super(kb_account_id, kb_payment_id, properties, context)
          rescue => e
            logger.warn("Unexpected exception while canceling pending kb_payment_id='#{t_info_plugins.last.kb_payment_id}', kb_payment_transaction_id='#{t_info_plugins.last.kb_transaction_payment_id}': #{e.message}\n#{e.backtrace.join("\n")}")
            t_info_plugins
          end
        else
          t_info_plugins_without_pending
        end
      end

      def search_payments(search_key, offset, limit, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(search_key, offset, limit, properties, context)
      end

      def add_payment_method(kb_account_id, kb_payment_method_id, payment_method_props, set_default, properties, context)
        all_properties = (payment_method_props.nil? || payment_method_props.properties.nil? ? [] : payment_method_props.properties) + properties
        token = find_value_from_properties(all_properties, 'token')

        if token.nil?
          # HPP flow
          options = {
              :skip_gw => true
          }
        else
          # Go to Paypal to get the Payer id (GetExpressCheckoutDetails call)
          payment_processor_account_id = find_value_from_properties(properties, :payment_processor_account_id)
          payment_processor_account_id ||= find_payment_processor_id_from_initial_call(kb_account_id, context.tenant_id, token)
          payer_id = find_payer_id(token, kb_account_id, context.tenant_id, payment_processor_account_id)
          options  = {
              :paypal_express_token         => token,
              :paypal_express_payer_id      => payer_id,
              :payment_processor_account_id => payment_processor_account_id
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
        jcontext = @kb_apis.create_context(context.tenant_id)

        all_properties = descriptor_fields + properties
        options = properties_to_hash(all_properties)

        kb_account = ::Killbill::Plugin::ActiveMerchant::Utils::LazyEvaluator.new { @kb_apis.account_user_api.get_account_by_id(kb_account_id, jcontext) }
        amount = (options[:amount] || '0').to_f
        currency = options[:currency] || kb_account.currency

        response = initiate_express_checkout(kb_account_id, amount, currency, all_properties, context)

        descriptor = super(kb_account_id, descriptor_fields, properties, context)
        descriptor.form_url = @private_api.to_express_checkout_url(response, context.tenant_id, options)
        descriptor.form_method = 'GET'
        descriptor.properties << build_property('token', response.token)

        # By default, pending payments are not created for HPP
        create_pending_payment = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(options, :create_pending_payment)
        if create_pending_payment
          payment_processor_account_id = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(options, :payment_processor_account_id)
          token_expiration_period = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(options, :token_expiration_period)
          custom_props = hash_to_properties(:from_hpp                     => true,
                                            :token                        => response.token,
                                            :payment_processor_account_id => payment_processor_account_id,
                                            :token_expiration_period      => token_expiration_period)
          payment_external_key = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(options, :payment_external_key)
          transaction_external_key = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(options, :transaction_external_key)

          kb_payment_method = (@kb_apis.payment_api.get_account_payment_methods(kb_account_id, false, [], jcontext).find { |pm| pm.plugin_name == 'killbill-paypal-express' })

          auth_mode = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(options, :auth_mode)
          # By default, the SALE mode is used.
          if auth_mode
            payment = @kb_apis.payment_api
                          .create_authorization(kb_account.send(:__instance_object__),
                                                kb_payment_method.id,
                                                nil,
                                                amount,
                                                currency,
                                                payment_external_key,
                                                transaction_external_key,
                                                custom_props,
                                                jcontext)
          else
            payment = @kb_apis.payment_api
                          .create_purchase(kb_account.send(:__instance_object__),
                                           kb_payment_method.id,
                                           nil,
                                           amount,
                                           currency,
                                           payment_external_key,
                                           transaction_external_key,
                                           custom_props,
                                           jcontext)
          end

          descriptor.properties << build_property('kb_payment_id', payment.id)
          descriptor.properties << build_property('kb_payment_external_key', payment.external_key)
          descriptor.properties << build_property('kb_transaction_id', payment.transactions.first.id)
          descriptor.properties << build_property('kb_transaction_external_key', payment.transactions.first.external_key)
        end

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

      def find_last_token(kb_account_id, kb_tenant_id)
        @response_model.last_token(kb_account_id, kb_tenant_id)
      end

      def find_payer_id(token, kb_account_id, kb_tenant_id, payment_processor_account_id)
        raise 'Could not find the payer_id: the token is missing' if token.blank?

        # Go to Paypal to get the Payer id (GetExpressCheckoutDetails call)
        payment_processor_account_id = payment_processor_account_id || :default
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

      def initiate_express_checkout(kb_account_id, amount, currency, properties, context)
        properties_hash = properties_to_hash(properties)

        with_baid = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :with_baid)

        options = {}
        options[:return_url] = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :return_url)
        options[:cancel_return_url] = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :cancel_return_url)
        options[:payment_processor_account_id] = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :payment_processor_account_id)
        options[:no_shipping] = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :no_shipping)

        max_amount_value = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :max_amount)
        if max_amount_value
          max_amount_in_cents = to_cents((max_amount_value || '0').to_f, currency)
          options[:max_amount] = max_amount_in_cents
        end

        amount_in_cents = amount.nil? ? nil : to_cents(amount, currency)
        response = @private_api.initiate_express_checkout(kb_account_id,
                                                          context.tenant_id.to_s,
                                                          amount_in_cents,
                                                          currency,
                                                          with_baid,
                                                          options)
        unless response.success?
          raise "Unable to initiate paypal express checkout: #{response.message}"
        end

        response
      end

      def authorize_or_purchase_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context, is_authorize = false)
        properties_hash = properties_to_hash properties
        payment_processor_account_id = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :payment_processor_account_id)
        transaction_type = is_authorize ? :AUTHORIZE : :PURCHASE
        api_call_type = is_authorize ? :authorize : :purchase

        # Callback from the plugin itself (HPP flow)
        if ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :from_hpp)
          token = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :token)
          message = {:payment_plugin_status => :PENDING,
                     :token_expiration_period => ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :token_expiration_period) || THREE_HOURS_AGO.to_s}
          response = @response_model.create(:api_call                     => :build_form_descriptor,
                                            :kb_account_id                => kb_account_id,
                                            :kb_payment_id                => kb_payment_id,
                                            :kb_payment_transaction_id    => kb_payment_transaction_id,
                                            :transaction_type             => transaction_type,
                                            :authorization                => token,
                                            :payment_processor_account_id => payment_processor_account_id,
                                            :kb_tenant_id                 => context.tenant_id,
                                            :success                      => true,
                                            :created_at                   => Time.now.utc,
                                            :updated_at                   => Time.now.utc,
                                            :message                      => message.to_json)
          transaction          = response.to_transaction_info_plugin(nil)
          transaction.amount   = amount
          transaction.currency = currency
          transaction
        else
          options = {}
          add_required_options(kb_payment_transaction_id, kb_payment_method_id, context, options)

          # We have a baid on file
          if options[:token]
            if is_authorize
              gateway_call_proc = Proc.new do |gateway, linked_transaction, payment_source, amount_in_cents, options|
                # Can't use default implementation: the purchase signature is for one-off payments only
                gateway.authorize_reference_transaction(amount_in_cents, options)
              end
            else
              gateway_call_proc = Proc.new do |gateway, linked_transaction, payment_source, amount_in_cents, options|
                # Can't use default implementation: the purchase signature is for one-off payments only
                gateway.reference_transaction(amount_in_cents, options)
              end
            end
          else
            # One-off payment
            options[:token] = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :token) || find_last_token(kb_account_id, context.tenant_id)
            if is_authorize
              gateway_call_proc  = Proc.new do |gateway, linked_transaction, payment_source, amount_in_cents, options|
                gateway.authorize(amount_in_cents, options)
              end
            else
              gateway_call_proc  = Proc.new do |gateway, linked_transaction, payment_source, amount_in_cents, options|
                gateway.purchase(amount_in_cents, options)
              end
            end
          end

          # Find the payment_processor_id if not provided
          payment_processor_account_id ||= find_payment_processor_id_from_initial_call(kb_account_id, context.tenant_id, options[:token])
          options[:payment_processor_account_id] = payment_processor_account_id

          # Populate the Payer id if missing
          options[:payer_id] = ::Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_hash, :payer_id)
          begin
            options[:payer_id] ||= find_payer_id(options[:token],
                                                 kb_account_id,
                                                 context.tenant_id,
                                                 payment_processor_account_id)
          rescue => e
            # Maybe invalid token?
            response = @response_model.create(:api_call                     => api_call_type,
                                              :kb_account_id                => kb_account_id,
                                              :kb_payment_id                => kb_payment_id,
                                              :kb_payment_transaction_id    => kb_payment_transaction_id,
                                              :transaction_type             => transaction_type,
                                              :authorization                => nil,
                                              :payment_processor_account_id => payment_processor_account_id,
                                              :kb_tenant_id                 => context.tenant_id,
                                              :success                      => false,
                                              :created_at                   => Time.now.utc,
                                              :updated_at                   => Time.now.utc,
                                              :message                      => { :payment_plugin_status => :CANCELED, :exception_class => e.class.to_s, :exception_message => e.message }.to_json)
            return response.to_transaction_info_plugin(nil)
          end

          properties = merge_properties(properties, options)
          dispatch_to_gateways(api_call_type, kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context, gateway_call_proc, nil, {:payer_id => options[:payer_id]})
        end
      end

      def find_payment_processor_id_from_initial_call(kb_account_id, kb_tenant_id, token)
        @response_model.initial_payment_account_processor_id kb_account_id, kb_tenant_id, token
      end

      def token_expired(transaction_plugin_info)
        paypal_response_id = find_value_from_properties(transaction_plugin_info.properties, 'paypalExpressResponseId')
        response = PaypalExpressResponse.find_by(:id => paypal_response_id)
        begin
          message_details = JSON.parse response.message
          expiration_period = (message_details['token_expiration_period'] || THREE_HOURS_AGO).to_i
        rescue
          expiration_period = THREE_HOURS_AGO.to_i
        end
        now = Time.parse(@clock.get_clock.get_utc_now.to_s)
        (now - transaction_plugin_info.created_date) >= expiration_period
      end

      def cancel_pending_transaction(transaction_plugin_info)
        @response_model.cancel_pending_payment transaction_plugin_info
      end
    end
  end
end
