require 'active_record'

ActiveRecord::Schema.define(:version => 20151008153635) do
  create_table "paypal_express_payment_methods", :force => true do |t|
    t.string   "kb_payment_method_id"     # NULL before Kill Bill knows about it
    t.string   "paypal_express_payer_id"  # NULL before the express checkout is completed
    t.string   "paypal_express_token"
    t.string   "token"                    # paypal-express baid, NULL before the express checkout is completed
    t.string   "cc_first_name"
    t.string   "cc_last_name"
    t.string   "cc_type"
    t.string   "cc_exp_month"
    t.string   "cc_exp_year"
    t.string   "cc_number"
    t.string   "cc_last_4"
    t.string   "cc_start_month"
    t.string   "cc_start_year"
    t.string   "cc_issue_number"
    t.string   "cc_verification_value"
    t.string   "cc_track_data"
    t.string   "address1"
    t.string   "address2"
    t.string   "city"
    t.string   "state"
    t.string   "zip"
    t.string   "country"
    t.boolean  "is_deleted",               :null => false, :default => false
    t.datetime "created_at",               :null => false
    t.datetime "updated_at",               :null => false
    t.string   "kb_account_id"
    t.string   "kb_tenant_id"
  end

  add_index(:paypal_express_payment_methods, :kb_account_id)
  add_index(:paypal_express_payment_methods, :kb_payment_method_id)

  create_table "paypal_express_transactions", :force => true do |t|
    t.integer  "paypal_express_response_id",  :null => false
    t.string   "api_call",                       :null => false
    t.string   "kb_payment_id",                  :null => false
    t.string   "kb_payment_transaction_id",      :null => false
    t.string   "transaction_type",               :null => false
    t.string   "payment_processor_account_id"
    t.string   "txn_id"                          # paypal-express transaction id
    # Both null for void
    t.integer  "amount_in_cents"
    t.string   "currency"
    t.datetime "created_at",                     :null => false
    t.datetime "updated_at",                     :null => false
    t.string   "kb_account_id",                  :null => false
    t.string   "kb_tenant_id",                   :null => false
  end

  add_index(:paypal_express_transactions, :kb_payment_id)

  create_table "paypal_express_responses", :force => true do |t|
    t.string   "api_call",          :null => false
    t.string   "kb_payment_id"
    t.string   "kb_payment_transaction_id"
    t.string   "transaction_type"
    t.string   "payment_processor_account_id"
    t.string   "message"
    t.string   "authorization"
    t.boolean  "fraud_review"
    t.boolean  "test"
    t.string   "token"
    t.string   "payer_id"
    t.string   "billing_agreement_id"
    t.string   "payer_name"
    t.string   "payer_email"
    t.string   "payer_country"
    t.string   "contact_phone"
    t.string   "ship_to_address_name"
    t.string   "ship_to_address_company"
    t.string   "ship_to_address_address1"
    t.string   "ship_to_address_address2"
    t.string   "ship_to_address_city"
    t.string   "ship_to_address_state"
    t.string   "ship_to_address_country"
    t.string   "ship_to_address_zip"
    t.string   "ship_to_address_phone"
    t.string   "receiver_info_business"
    t.string   "receiver_info_receiver"
    t.string   "receiver_info_receiverid"
    t.string   "payment_info_transactionid"
    t.string   "payment_info_parenttransactionid"
    t.string   "payment_info_receiptid"
    t.string   "payment_info_transactiontype"
    t.string   "payment_info_paymenttype"
    t.string   "payment_info_paymentdate"
    t.string   "payment_info_grossamount"
    t.string   "payment_info_feeamount"
    t.string   "payment_info_taxamount"
    t.string   "payment_info_exchangerate"
    t.string   "payment_info_paymentstatus"
    t.string   "payment_info_pendingreason"
    t.string   "payment_info_reasoncode"
    t.string   "payment_info_protectioneligibility"
    t.string   "payment_info_protectioneligibilitytype"
    t.string   "payment_info_shipamount"
    t.string   "payment_info_shiphandleamount"
    t.string   "payment_info_shipdiscount"
    t.string   "payment_info_insuranceamount"
    t.string   "payment_info_subject"
    t.string   "avs_result_code"
    t.string   "avs_result_message"
    t.string   "avs_result_street_match"
    t.string   "avs_result_postal_match"
    t.string   "cvv_result_code"
    t.string   "cvv_result_message"
    t.boolean  "success"
    t.datetime "created_at",        :null => false
    t.datetime "updated_at",        :null => false
    t.string   "kb_account_id"
    t.string   "kb_tenant_id"
  end
end
