require 'active_record'

ActiveRecord::Schema.define(:version => 20130311153635) do
  create_table "paypal_express_payment_methods", :force => true do |t|
    t.string   "kb_account_id",           :null => false
    t.string   "kb_payment_method_id"     # NULL before Killbill knows about it
    t.string   "paypal_express_payer_id"  # NULL before the express checkout is completed
    t.string   "paypal_express_token",    :null => false, :unique => true
    t.boolean  "is_deleted",              :null => false, :default => false
    t.datetime "created_at",              :null => false
    t.datetime "updated_at",              :null => false
  end

  create_table "paypal_express_transactions", :force => true do |t|
    t.integer  "paypal_express_response_id", :null => false
    t.string   "api_call",                   :null => false
    t.string   "kb_payment_id",              :null => false
    t.string   "paypal_express_txn_id",      :null => false
    t.integer  "amount_in_cents",            :null => false
    t.datetime "created_at",                 :null => false
    t.datetime "updated_at",                 :null => false
  end

  create_table "paypal_express_responses", :force => true do |t|
    t.string   "api_call",        :null => false
    t.string   "kb_payment_id"
    t.string   "message"
    t.string   "authorization"
    t.boolean  "fraud_review"
    t.boolean  "test"
    t.string   "token"
    t.string   "payer_id"
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
  end
end