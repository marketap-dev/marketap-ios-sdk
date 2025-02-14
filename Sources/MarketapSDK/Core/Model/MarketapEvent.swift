//
//  MarketapEvent.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

enum MarketapEvent: String {
    case login = "mkt_login"
    case logout = "mkt_logout"
    case view = "mkt_page_view"
    case purchase = "mkt_purchase"
    case signup = "mkt_signup"
    case sessionStart = "mkt_session_start"
    case sessionEnd = "mkt_session_end"
    case search = "mkt_search"
    case productView = "mkt_product_view"
    case addToCart = "mkt_add_to_cart"
    case addToWishlist = "mkt_add_to_wishlist"
    case biginCheckout = "mkt_begin_checkout"
    case cartView = "mkt_cart_view"
}
