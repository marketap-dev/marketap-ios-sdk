//
//  PurchaseView.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/19/25.
//

import SwiftUI
import MarketapSDK

struct PurchaseView: View {
    @Binding var product: (String, Double, String)?
    @Binding var cartItems: [CartItem]
    @Binding var isPresented: Bool
    @State var purchase: Bool = false

    var body: some View {
        NavigationView {
            let name = product?.0 ?? "상품"
            let priceDouble = product?.1 ?? 9999
            let price = formatPrice(priceDouble)
            VStack(spacing: 20) {
                Text(name)
                    .font(.largeTitle)
                    .bold()

                Text(price)
                    .font(.title)
                    .foregroundColor(.gray)

                Button(
                    action: {
                        Marketap.track(
                            eventName: "mkt_add_to_cart",
                            eventProperties: ["mkt_items": [[
                                "mkt_product_id": name,
                                "mkt_product_name": name,
                                "mkt_product_price": priceDouble,
                                "mkt_quantity": 1,
                                "mkt_category1": product?.2 ?? "카테고리"
                            ]]]
                        )

                    let newItem = CartItem(name: name, price: priceDouble)
                    cartItems.append(newItem)
                    saveCartItems()
                    isPresented = false
                }) {
                    Text("🛒 장바구니에 추가")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                Button(action: {
                    purchase = true
                    isPresented = false
                }) {
                    Text("구매")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                Button(action: {
                    isPresented = false
                }) {
                    Text("닫기")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("구매하기")
            .onAppear {
                Marketap.track(eventName: "mkt_product_view", eventProperties: ["mkt_items": [[
                    "mkt_product_id": name,
                    "mkt_product_name": name,
                    "mkt_product_price": priceDouble,
                    "mkt_quantity": 1,
                    "mkt_category1": product?.2 ?? "카테고리"
                ]]])
                Marketap.trackPageView(eventProperties: ["mkt_page_title": "구매하기"])
            }
            .onDisappear {
                if purchase {
                    Marketap.trackPurchase(revenue: priceDouble, eventProperties: ["mkt_items": [[
                        "mkt_product_id": name,
                        "mkt_product_name": name,
                        "mkt_product_price": priceDouble,
                        "mkt_quantity": 1,
                        "mkt_category1": product?.2 ?? "카테고리"
                    ]]])
                }
            }
        }
    }

    private func saveCartItems() {
        if let encoded = try? JSONEncoder().encode(cartItems) {
            UserDefaults.standard.set(encoded, forKey: "cartItems")
        }
    }

    private func formatPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₩"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "₩\(Int(price))"
    }
}
