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


class InAppMessageServiceTests: XCTestCase {
    var service: InAppMessageService!
    var mockAPI: MockMarketapAPIForIAM!
    var mockCache: MockMarketapCache!
    var mockEventService: EventService!

    override func setUp() {
        super.setUp()
        mockAPI = MockMarketapAPIForIAM()
        mockCache = MockMarketapCache()
        mockEventService = EventService(api: mockAPI, cache: mockCache)

        service = InAppMessageService(api: mockAPI, cache: mockCache, eventService: mockEventService)
    }

    override func tearDown() {
        service = nil
        mockAPI = nil
        mockCache = nil
        mockEventService = nil
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
            html: "<html><body>Test Campaign</body></html>"
        )

        let fetchResponse = InAppCampaignFetchResponse(
            checksum: "checksum123",
            campaigns: [expectedCampaign]
        )

        mockAPI.fetchCampaignsResult = .success(fetchResponse)

        let expectation = self.expectation(description: "Campaigns fetched")

        service.fetchCampaigns(force: true) { campaigns in
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
            html: "<html><body>Cached Campaign</body></html>"
        )

        service.lastFetch = Date()
        service.campaigns = [cachedCampaign]

        let expectation = self.expectation(description: "Campaigns loaded from cache")

        service.fetchCampaigns(force: false) { campaigns in
            XCTAssertEqual(campaigns, [cachedCampaign])
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testFetchCampaigns_Failure() {
        mockAPI.fetchCampaignsResult = .failure(.serverError(statusCode: 500))

        let expectation = self.expectation(description: "Fetch campaigns failed")

        service.fetchCampaigns(force: true) { campaigns in
            XCTAssertEqual(campaigns.count, 0) // 실패하면 빈 배열 반환
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testEventServiceIntegration() {
        class MockDelegate: EventServiceDelegate {
            var userIdChangedCalled = false
            var eventTracked: IngestEventRequest?

            func handleUserIdChanged() {
                userIdChangedCalled = true
            }

            func onEvent(eventRequest: IngestEventRequest, device: Device) {
                eventTracked = eventRequest
            }
        }

        let mockDelegate = MockDelegate()
        mockEventService.delegate = mockDelegate

        mockEventService.trackEvent(eventName: "test_event", eventProperties: ["key": "value"])

        XCTAssertNotNil(mockDelegate.eventTracked)
        XCTAssertEqual(mockDelegate.eventTracked?.name, "test_event")
    }
}
