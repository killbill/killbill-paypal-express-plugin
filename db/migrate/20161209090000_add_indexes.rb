class AddIndexes < ActiveRecord::Migration

  def change
    add_index(:paypal_express_responses, :kb_account_id, :name => 'idx_paypal_express_responses_on_kb_account_id')
    add_index(:paypal_express_responses, :payer_email, :name => 'idx_paypal_express_responses_on_payer_email')
  end
end
