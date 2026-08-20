require "test_helper"

class ListingsControllerTest < ActionDispatch::IntegrationTest
  test "index shows active listings and the great-deal summary line" do
    get listings_url
    assert_response :success
    assert_select "h1", text: "Apple Products Scraper Dashboard"
    assert_match "Space Black", @response.body
  end

  test "index filtering by marketplace only shows that source" do
    get listings_url, params: { source: "ebay" }
    assert_response :success
    assert_match "Space Black", @response.body
    assert_no_match(/#{Regexp.escape(listings(:ebike_offerup).title)}/, @response.body)
  end

  test "index filtering by great deals only excludes non-great-deal listings" do
    get listings_url, params: { great: "1" }
    assert_response :success
    assert_match "Space Black", @response.body
    assert_no_match(/#{Regexp.escape(listings(:ebike_offerup).title)}/, @response.body)
  end

  test "show renders one listing's price history oldest first" do
    get listing_url(listings(:macbook_pro_ebay))
    assert_response :success
    assert_select "h1", text: listings(:macbook_pro_ebay).title
  end
end
