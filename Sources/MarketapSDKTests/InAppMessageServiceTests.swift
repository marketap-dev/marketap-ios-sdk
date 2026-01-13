//
//  InAppMessageServiceTests.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import XCTest
@testable import MarketapSDK

class MockMarketapAPIForIAM: MarketapAPIProtocol {
    var fetchCampaignsResult: Result<InAppCampaignFetchResponse, MarketapError>?

    func get<T: Decodable>(
        baseURL: MarketapAPI.BaseURL,
        path: String,
        queryItems: [URLQueryItem]?,
        responseType: T.Type,
        completion: ((Result<T, MarketapError>) -> Void)?
    ) {
        if let fetchCampaignsResult = fetchCampaignsResult as? Result<T, MarketapError> {
            completion?(fetchCampaignsResult)
        }
    }

    func request<T: Decodable, U: Encodable>(
        baseURL: MarketapAPI.BaseURL,
        path: String,
        body: U,
        responseType: T.Type,
        completion: ((Result<T, MarketapError>) -> Void)?
    ) {
        if let fetchCampaignsResult = fetchCampaignsResult as? Result<T, MarketapError> {
            completion?(fetchCampaignsResult)
        }
    }

    func requestWithoutResponse<U: Encodable>(
        baseURL: MarketapAPI.BaseURL,
        path: String,
        body: U,
        completion: ((Result<Void, MarketapError>) -> Void)?
    ) {
        completion?(.success(())) // 성공 응답 처리
    }
}

class CustomHandlerStor: MarketapCustomHandlerStoreProtocol {
    func handleClick(_ event: MarketapSDK.MarketapClickEvent) {

    }
    
    func setClickHandler(_ handler: @escaping (MarketapSDK.MarketapClickEvent) -> Void) {

    }
}

class InAppMessageServiceTests: XCTestCase {
    var service: InAppMessageService!
    var mockAPI: MockMarketapAPIForIAM!
    var mockCache: MockMarketapCache!

    override func setUp() {
        super.setUp()
        mockAPI = MockMarketapAPIForIAM()
        mockCache = MockMarketapCache()

        service = InAppMessageService(customHandlerStore: CustomHandlerStor(), api: mockAPI, cache: mockCache)
    }

    override func tearDown() {
        service = nil
        mockAPI = nil
        mockCache = nil
        super.tearDown()
    }

    func testFetchCampaigns_Success() {
        let expectedCampaign = InAppCampaign(
            id: "test_campaign",
            layout: Layout(layoutType: "MODAL", layoutSubType: "CENTER", orientations: ["portrait"]),
            triggerEventCondition: EventTriggerCondition(
                condition: Condition(
                    eventFilter: EventFilter(eventName: "test_event"),
                    propertyConditions: nil
                ),
                frequencyCap: FrequencyCap(limit: 5, durationMinutes: 60),
                delayMinutes: 10
            ),
            html: "<html><body>Test Campaign</body></html>",
            updatedAt: "\(Date())"
        )

        let fetchResponse = InAppCampaignFetchResponse(
            checksum: "checksum123",
            campaigns: [expectedCampaign]
        )

        mockAPI.fetchCampaignsResult = .success(fetchResponse)

        let expectation = self.expectation(description: "Campaigns fetched")

        service.fetchCampaigns(force: true, inTimeout: nil) { campaigns in
            XCTAssertEqual(campaigns, [expectedCampaign])
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testFetchCampaigns_CacheUsed() {
        let cachedCampaign = InAppCampaign(
            id: "cached_campaign",
            layout: Layout(layoutType: "MODAL", layoutSubType: "CENTER", orientations: ["portrait"]),
            triggerEventCondition: EventTriggerCondition(
                condition: Condition(
                    eventFilter: EventFilter(eventName: "test_event"),
                    propertyConditions: nil
                ),
                frequencyCap: FrequencyCap(limit: 5, durationMinutes: 60),
                delayMinutes: 10
            ),
            html: "<html><body>Cached Campaign</body></html>",
            updatedAt: "\(Date())"
        )

        service.lastFetch = Date()
        service.campaigns = [cachedCampaign]

        let expectation = self.expectation(description: "Campaigns loaded from cache")

        service.fetchCampaigns(force: false, inTimeout: nil) { campaigns in
            XCTAssertEqual(campaigns, [cachedCampaign])
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testFetchCampaigns_Failure() {
        mockAPI.fetchCampaignsResult = .failure(.serverError(statusCode: 500))

        let expectation = self.expectation(description: "Fetch campaigns failed")

        service.fetchCampaigns(force: true, inTimeout: nil) { campaigns in
            XCTAssertEqual(campaigns.count, 0) // 실패하면 빈 배열 반환
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }
}
