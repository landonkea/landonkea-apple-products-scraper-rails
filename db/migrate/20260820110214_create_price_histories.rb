# This migration builds the "price_histories" table -- one row per
# price a listing has ever been observed at. Unlike the "listings"
# table (which only ever holds a listing's CURRENT price), this table
# never overwrites anything -- it's an append-only timeline, which is
# exactly what powers the "price history for this listing" chart on
# the dashboard and the price-drop alert logic.
class CreatePriceHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :price_histories do |t|
      # references :listing adds a listing_id column and a foreign key
      # constraint, this row always belongs to exactly one listing, and
      # the database will refuse to save a price_history row that points
      # at a listing that doesn't exist.
      t.references :listing, null: false, foreign_key: true

      # The price observed at this point in time.
      t.float :price_usd, null: false

      # When we recorded this price point (not necessarily "right now" --
      # this gets set to the moment the scrape ran, which the job may
      # backdate slightly if it started a few seconds earlier).
      t.datetime :recorded_at, null: false, index: true

      # created_at/updated_at bookkeeping columns, same as every table.
      t.timestamps
    end
  end
end
