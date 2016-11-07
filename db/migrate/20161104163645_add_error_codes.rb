class AddErrorCodes < ActiveRecord::Migration

  def change
    reversible do |dir|
      change_table :paypal_express_responses do |t|
        dir.up { t.add_column :error_code, :integer }
        dir.down { t.remove_column :error_code }
      end
    end
  end
end
