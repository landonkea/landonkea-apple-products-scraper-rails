# A follow-up migration -- the original create_listings migration left
# this column out, but several scrapers do have a real city/region to
# report (Craigslist's "Tempe", Apple Refurb's "Apple Refurbished"),
# and the e-bike search filters listings down to the Phoenix, AZ area,
# so the dashboard needs somewhere to show that.
class AddLocationToListings < ActiveRecord::Migration[8.1]
  def change
    # A free-text city/region string. Optional -- several marketplaces
    # (eBay, Swappa, Best Buy, Newegg) never expose a structured
    # location at all, so this stays blank for those listings.
    add_column :listings, :location, :string
  end
end
