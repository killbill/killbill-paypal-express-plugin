require 'spec_helper'
require_relative 'hpp_spec_helpers'
require_relative 'build_plugin_helpers'
require_relative 'hpp_spec_common'

ActiveMerchant::Billing::Base.mode = :test

describe Killbill::PaypalExpress::PaymentPlugin do
  include ::Killbill::Plugin::ActiveMerchant::RSpec
  include ::Killbill::PaypalExpress::BuildPluginHelpers
  include ::Killbill::PaypalExpress::HppSpecHelpers

  context 'hpp test with billing agreement', :single_account => true do
    before(:all) do
      @payment_processor_account_id = 'default'
      @plugin = build_start_paypal_plugin
      hpp_setup
    end

    include_examples 'hpp_spec_common', :with_baid => true, :billing_agreement_type => 'MerchantInitiatedBillingSingleAgreement'
  end
end