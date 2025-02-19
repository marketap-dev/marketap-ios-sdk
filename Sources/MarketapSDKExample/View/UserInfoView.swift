//
//  UserInfoView.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/19/25.
//

import SwiftUI
import MarketapSDK

struct UserInfoView: View {
    @Binding var isPresented: Bool

    @Environment(\.presentationMode) var presentationMode
    @State private var name: String = UserDefaults.standard.string(forKey: "userName") ?? ""
    @State private var email: String = UserDefaults.standard.string(forKey: "userEmail") ?? ""
    @State private var phone: String = UserDefaults.standard.string(forKey: "userPhone") ?? ""
    @State private var isLoggedIn: Bool = UserDefaults.standard.string(forKey: "userName") != nil

    var body: some View {
        NavigationView {
            Form {
                if isLoggedIn {
                    // ✅ 유저 정보 표시 (읽기 전용)
                    Section(header: Text("내 정보")) {
                        Text("이름: \(name)")
                        Text("이메일: \(email)")
                        Text("전화번호: \(phone)")
                    }

                    // ✅ 로그아웃 버튼
                    Button(action: logout) {
                        Text("로그아웃")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                } else {
                    // ✅ 로그인 입력 폼
                    Section(header: Text("로그인")) {
                        TextField("이름", text: $name)
                            .textContentType(.name)
                        TextField("이메일", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                        TextField("전화번호", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    }

                    // ✅ 로그인 버튼
                    Button(action: login) {
                        Text("로그인")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(name.isEmpty || email.isEmpty) // 입력값 없으면 버튼 비활성화
                }
            }
            .navigationTitle("내 정보")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                Marketap.trackPageView(eventProperties: ["mkt_page_title": "내 정보"])
            }
        }
    }

    // ✅ 로그인 처리 (UserDefaults 저장)
    private func login() {
        Marketap.login(
            userId: phone,
            userProperties: [
                "mkt_name": name,
                "mkt_email": email,
                "mkt+mkt_phone_number": phone
            ],
            eventProperties: nil
        )

        UserDefaults.standard.set(name, forKey: "userName")
        UserDefaults.standard.set(email, forKey: "userEmail")
        UserDefaults.standard.set(phone, forKey: "userPhone")
        isLoggedIn = true
    }

    // ✅ 로그아웃 처리 (UserDefaults 삭제)
    private func logout() {
        Marketap.logout(eventProperties: nil)

        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "userName")
        UserDefaults.standard.removeObject(forKey: "userEmail")
        UserDefaults.standard.removeObject(forKey: "userPhone")
        name = ""
        email = ""
        phone = ""
        isLoggedIn = false
    }
}

