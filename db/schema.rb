# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_20_110421) do
  create_table "listings", force: :cascade do |t|
    t.float "battery_ah"
    t.integer "battery_voltage"
    t.float "battery_wh"
    t.string "brake_type"
    t.string "brand"
    t.string "chip"
    t.string "condition"
    t.integer "cpu_cores"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.float "deal_score"
    t.boolean "fat_tire"
    t.datetime "first_seen_at", null: false
    t.boolean "folding"
    t.integer "gpu_cores"
    t.boolean "is_active", default: true, null: false
    t.boolean "is_great_deal", default: false, null: false
    t.datetime "last_seen_at", null: false
    t.string "listing_id", null: false
    t.string "location"
    t.integer "motor_watts_nominal"
    t.integer "motor_watts_peak"
    t.float "price_usd", null: false
    t.string "product_type", null: false
    t.integer "ram_gb"
    t.float "screen_size"
    t.string "search_name", null: false
    t.string "source", null: false
    t.boolean "step_through"
    t.integer "storage_gb"
    t.boolean "suspension"
    t.string "title", null: false
    t.boolean "ul_certified"
    t.datetime "updated_at", null: false
    t.text "url", null: false
    t.integer "weight_capacity_lb"
    t.float "wheel_size_in"
    t.index ["is_active"], name: "index_listings_on_is_active"
    t.index ["last_seen_at"], name: "index_listings_on_last_seen_at"
    t.index ["price_usd"], name: "index_listings_on_price_usd"
    t.index ["product_type"], name: "index_listings_on_product_type"
    t.index ["search_name"], name: "index_listings_on_search_name"
    t.index ["source", "listing_id"], name: "index_listings_on_source_and_listing_id", unique: true
    t.index ["source"], name: "index_listings_on_source"
  end

  create_table "price_histories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "listing_id", null: false
    t.float "price_usd", null: false
    t.datetime "recorded_at", null: false
    t.datetime "updated_at", null: false
    t.index ["listing_id"], name: "index_price_histories_on_listing_id"
    t.index ["recorded_at"], name: "index_price_histories_on_recorded_at"
  end

  add_foreign_key "price_histories", "listings"
end
