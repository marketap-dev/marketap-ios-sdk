//
//  CartView.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/19/25.
//

import SwiftUI
import MarketapSDK

struct CartItem: Codable, Identifiable {
    let id: UUID = UUID()
    let name: String
    let price: Double
}

struct CartView: View {
    @Binding var cartItems: [CartItem] // ✅ 장바구니 데이터
    @Binding var isPresented: Bool

    @State private var showAlert = false
    @State private var selectedItem: CartItem?

    var body: some View {
        NavigationView {
            VStack {
                if cartItems.isEmpty {
                    Text("🛒 장바구니가 비었습니다.")
                        .font(.title)
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        ForEach(cartItems) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name) // ✅ 상품명
                                        .font(.headline)

                                    Text(formatPrice(item.price)) // ✅ 가격
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                Spacer()

                                // ✅ 개별 삭제 버튼
                                Button(action: {
                                    selectedItem = item
                                    showAlert = true
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .padding()
                                }
                            }
                        }
                        .onDelete(perform: removeItem) // ✅ 삭제 기능
                    }
                }

                Button(action: {
                    isPresented = false // 장바구니 닫기
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
            .navigationTitle("장바구니")
            .toolbar {
                if !cartItems.isEmpty {
                    EditButton() // ✅ 편집 버튼 추가
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("삭제 확인"),
                    message: Text("\(selectedItem?.name ?? "")을(를) 장바구니에서 삭제할까요?"),
                    primaryButton: .destructive(Text("삭제")) {
                        if let item = selectedItem {
                            removeSpecificItem(item)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
            .onAppear {
                Marketap.trackPageView(eventProperties: ["mkt_page_title": "장바구니"])
            }
        }
    }

    /// ✅ 선택한 아이템을 삭제하는 함수
    private func removeSpecificItem(_ item: CartItem) {
        if let index = cartItems.firstIndex(where: { $0.id == item.id }) {
            cartItems.remove(at: index)
            saveCartItems()
        }
    }

    /// ✅ 장바구니에서 아이템 삭제 후 저장 (기존 기능)
    private func removeItem(at offsets: IndexSet) {
        cartItems.remove(atOffsets: offsets)
        saveCartItems()
    }

    /// ✅ 장바구니 데이터를 UserDefaults에 저장
    private func saveCartItems() {
        if let encoded = try? JSONEncoder().encode(cartItems) {
            UserDefaults.standard.set(encoded, forKey: "cartItems")
        }
    }

    /// ✅ 가격을 ₩ (원화) 형식으로 변환
    private func formatPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₩"
        formatter.maximumFractionDigits = 0 // 소수점 제거
        return formatter.string(from: NSNumber(value: price)) ?? "₩\(Int(price))"
    }
}
