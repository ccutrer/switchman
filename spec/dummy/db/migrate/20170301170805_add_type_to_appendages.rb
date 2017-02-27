class AddTypeToAppendages < ActiveRecord::Migration
  def change
    add_column :appendages, :type, :string, null: false
  end
end
