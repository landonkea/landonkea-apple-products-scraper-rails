# One price observation for one listing at one moment in time. Rows
# here are never edited or overwritten -- each one is a permanent
# point on that listing's price timeline, which is what lets the
# dashboard draw "here's what this listing's price has actually done."
class PriceHistory < ApplicationRecord
  # Every price point belongs to exactly one listing.
  belongs_to :listing

  # A price point needs a real, positive dollar amount and a timestamp
  # saying when it was observed -- both are required for the history
  # table/chart to make sense.
  validates :price_usd, presence: true, numericality: { greater_than: 0 }
  validates :recorded_at, presence: true

  # Oldest-to-newest is the natural reading order for a price timeline
  # (a chart or table reads left-to-right as "then... then... now").
  scope :chronological, -> { order(:recorded_at) }

  # Only write a new row when the price is genuinely new or has
  # changed since the last recorded point for this listing -- called by
  # the scrape job on every save, not automatically on every update, so
  # a listing whose price never moves doesn't grow a near-duplicate row
  # on every single scrape run.
  def self.record_if_changed!(listing, price_usd)
    last = listing.price_histories.chronological.last
    return false if last && last.price_usd == price_usd

    listing.price_histories.create!(price_usd: price_usd, recorded_at: Time.current)
    true
  end
end
