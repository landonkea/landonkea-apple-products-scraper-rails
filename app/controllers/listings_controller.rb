# Serves the dashboard -- the screen a person actually looks at to see
# what the scraper found. Nothing here writes to the database; both
# actions only ever read and display what ScrapeListingsJob already saved.
class ListingsController < ApplicationController
  # `index` handles GET /listings (and GET / via the root route).
  def index
    # Start from every listing our last scrape still confirmed is
    # active, best-scored first.
    scope = Listing.active.best_deals_first

    # Each of these only applies when the matching dropdown/checkbox
    # was actually used, so the default view still shows everything.
    scope = scope.from_source(params[:source])
    scope = scope.for_search(params[:search_name])
    scope = scope.great_deals if params[:great].present?

    @listings = scope

    # Builds the dropdown option lists straight from whatever's
    # actually in the (active) database right now, rather than a
    # hardcoded list, so they stay accurate as new sources/searches
    # show up.
    @sources = Listing.active.distinct.pluck(:source).compact.sort
    @search_names = Listing.active.distinct.pluck(:search_name).compact.sort

    # A short stats line at the top of the page, mirroring the run
    # summary Python's main.py printed to the terminal after every scrape.
    @total_count = Listing.active.count
    @great_deal_count = Listing.active.great_deals.count
  end

  # `show` handles GET /listings/:id -- one listing's own page, with
  # its full recorded price history (oldest first, so the table reads
  # top-to-bottom as "then... then... now").
  def show
    @listing = Listing.find(params[:id])
    @price_histories = @listing.price_histories.chronological
  end
end
