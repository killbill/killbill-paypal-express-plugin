class AddIndexes < ActiveRecord::Migration

  def change
    add_index(:paypal_express_transactions, :paypal_express_response_id, :name => 'idx_paypal_express_transactions_on_paypal_express_response_id')
    add_index(:paypal_express_responses, [:kb_payment_id, :kb_tenant_id], :name => 'idx_paypal_express_responses_on_kb_payment_id_kb_tenant_id')
  end
end
