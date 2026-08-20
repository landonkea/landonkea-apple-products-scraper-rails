# A background job is work that runs outside the normal request/
# response cycle -- instead of a dashboard visitor waiting several
# minutes for a scrape across 4 searches and 10 marketplaces to
# finish, Solid Queue (Rails 8's built-in job backend, already wired up
# by `rails new`) runs this on its own schedule (see
# config/recurring.yml) and the dashboard just reads whatever's
# already in the database whenever someone loads it.
class ScrapeListingsJob < ApplicationJob
  # `:default` puts this job on Solid Queue's default work queue --
  # fine here since this app only has the one kind of background job.
  queue_as :default

  # `perform` is the method Solid Queue actually calls when it's time
  # to run this job -- all the real work lives in ScrapeRunner so it
  # stays easy to trigger by hand from the Rails console too, not just
  # from the schedule.
  def perform(*args)
    ScrapeRunner.call
  end
end
