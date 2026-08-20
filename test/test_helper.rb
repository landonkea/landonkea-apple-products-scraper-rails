ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
# WebMock replaces Ruby's real HTTP layer during tests -- any scraper
# test that forgets to stub a request gets a loud failure instead of a
# real network call going out, which is what keeps this whole suite
# fast, offline-safe, and free of "it worked on my machine" flakiness.
require "webmock/minitest"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
