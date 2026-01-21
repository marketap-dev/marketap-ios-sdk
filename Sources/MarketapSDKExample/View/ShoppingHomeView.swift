//
//  ShoppingHomeView.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/19/25.
//

import SwiftUI
import MarketapSDK


struct ShoppingHomeView: View {
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared

    @State private var selectedCategory: String = "전체"
    @State private var isShowingPurchase = false
    @State private var selectedProduct: (String, Double, String)? = nil

    @State private var isShowingCart = false
    @State private var isShowingUserInfo = false
    @State private var cartItems: [CartItem] = []

    let categories = ["전체", "의류", "전자제품", "가구", "스포츠", "도서", "음식", "주방용품", "생활용품"]

    let products: [(String, Double, String)] = [
        ("티셔츠", 19900, "의류"),
        ("청바지", 49900, "의류"),
        ("스마트폰", 999000, "전자제품"),
        ("노트북", 1490000, "전자제품"),
        ("태블릿", 750000, "전자제품"),
        ("무선 이어폰", 199000, "전자제품"),
        ("스마트 워치", 299000, "전자제품"),
        ("소파", 890000, "가구"),
        ("책상", 159000, "가구"),
        ("의자", 99000, "가구"),
        ("러닝화", 129000, "스포츠"),
        ("축구공", 35000, "스포츠"),
        ("요가매트", 45000, "스포츠"),
        ("헬스 장갑", 29000, "스포츠"),
        ("소설책", 12900, "도서"),
        ("요리책", 22000, "도서"),
        ("과학잡지", 15000, "도서"),
        ("커피머신", 199000, "주방용품"),
        ("토스터", 49000, "주방용품"),
        ("공기청정기", 350000, "생활용품"),
        ("전기장판", 120000, "생활용품"),
        ("햄버거 세트", 8900, "음식"),
        ("초콜릿", 5500, "음식")
    ]

    var filteredProducts: [(String, Double, String)] {
        if selectedCategory == "전체" {
            return products
        } else {
            return products.filter { $0.2 == selectedCategory }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(categories, id: \.self) { category in
                            Text(category)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(selectedCategory == category ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(selectedCategory == category ? .white : .black)
                                .cornerRadius(20)
                                .onTapGesture {
                                    selectedCategory = category
                                }
                        }
                    }
                    .padding(.horizontal)
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(filteredProducts, id: \.0) { product in
                            ProductCard(name: product.0, price: formatPrice(product.1)) {
                                self.selectedProduct = product
                                self.isShowingPurchase = true
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("홈")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { isShowingUserInfo = true }) {
                            Image(systemName: "person.crop.circle")
                        }
                        Button(action: { isShowingCart = true }) {
                            Image(systemName: "cart")
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingPurchase) {
                PurchaseView(product: $selectedProduct, cartItems: $cartItems, isPresented: $isShowingPurchase)
            }
            .fullScreenCover(isPresented: $isShowingCart) {
                CartView(cartItems: $cartItems, isPresented: $isShowingCart)
            }
            .fullScreenCover(isPresented: $isShowingUserInfo) {
                UserInfoView(isPresented: $isShowingUserInfo)
            }
            .onAppear {
                Marketap.trackPageView(eventProperties: ["mkt_page_title": "홈"])
                loadCartItems()
            }
            .onChange(of: deepLinkManager.destination) { destination in
                handleDeepLink(destination)
            }
            .onAppear {
                // 앱 시작 시 대기 중인 딥링크 처리
                handleDeepLink(deepLinkManager.destination)
            }
        }
    }

    private func handleDeepLink(_ destination: DeepLinkDestination?) {
        guard let destination = destination else { return }

        switch destination {
        case .cart:
            isShowingCart = true
        case .user:
            isShowingUserInfo = true
        case .product(let name):
            if let product = products.first(where: { $0.0 == name }) {
                selectedProduct = product
                isShowingPurchase = true
            }
        case .category(let name):
            if categories.contains(name) {
                selectedCategory = name
            }
        default:
            break
        }

        deepLinkManager.clearDestination()
    }

    private func formatPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₩"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "₩\(Int(price))"
    }

    private func loadCartItems() {
        if let savedData = UserDefaults.standard.data(forKey: "cartItems"),
           let decoded = try? JSONDecoder().decode([CartItem].self, from: savedData) {
            cartItems = decoded
        }
    }
}

struct ProductCard: View {
    let name: String
    let price: String
    let onPurchaseTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 100)
                .overlay(Text("상품 이미지").font(.caption))

            Text(name)
                .font(.headline)
            Text(price)
                .font(.subheadline)
                .foregroundColor(.gray)

            Button(action: onPurchaseTap) {
                Text("구매하기")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct ShoppingHomeView_Previews: PreviewProvider {
    static var previews: some View {
        ShoppingHomeView()
    }
}
