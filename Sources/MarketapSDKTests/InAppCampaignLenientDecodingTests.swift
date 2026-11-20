import XCTest
@testable import MarketapSDK

final class InAppCampaignLenientDecodingTests: XCTestCase {
    private func campaign(id: String, dataType: String = "STRING", op: String = "EQUAL", path: String = "EVENT") -> String {
        """
        {"id":"\(id)","layout":{"layoutType":"MODAL","layoutSubType":"IMAGE","orientations":["PORTRAIT"]},
         "triggerEventCondition":{"condition":{"eventFilter":{"eventName":"view"},
           "propertyConditions":[[{"extractionStrategy":{"propertySchema":{"id":"","name":"p","dataType":"\(dataType)","path":"\(path)"}},
             "operator":"\(op)","targetValues":["a"]}]]}},
         "updatedAt":"2026-01-01T00:00:00Z"}
        """
    }

    private func decodeList(_ campaigns: [String]) throws -> InAppCampaignFetchResponse {
        let json = "{\"code\":200,\"message\":\"ok\",\"data\":{\"checksum\":\"c\",\"campaigns\":[\(campaigns.joined(separator: ","))]}}"
        return try JSONDecoder().decode(ServerResponse<InAppCampaignFetchResponse>.self, from: Data(json.utf8)).data
    }

    func testUnknownConditionValuesSkipOnlyThatCampaign() throws {
        let response = try decodeList([
            campaign(id: "ok"),
            campaign(id: "type", dataType: "OBJECT_ARRAY"),
            campaign(id: "operator", op: "ANNIVERSARY_PAST"),
            campaign(id: "path", path: "COUPON"),
            campaign(id: "ok2"),
        ])

        XCTAssertEqual(response.campaigns?.map { $0.id }, ["ok", "ok2"])
        XCTAssertEqual(response.checksum, "c")
    }

    func testStringArrayTypeIsDecodedUnderBothNames() throws {
        let response = try decodeList([
            campaign(id: "server", dataType: "STRING_ARRAY", op: "ARRAY_LIKE"),
            campaign(id: "legacy", dataType: "ARRAY_STRING", op: "ARRAY_LIKE"),
        ])

        let types = response.campaigns?.map {
            $0.triggerEventCondition.condition.propertyConditions?[0][0].extractionStrategy.propertySchema.dataType
        }
        XCTAssertEqual(types, [.arrayString, .arrayString])

        let cached = try JSONEncoder().encode(response.campaigns)
        XCTAssertEqual(try JSONDecoder().decode([InAppCampaign].self, from: cached), response.campaigns)
        let cachedText = String(decoding: cached, as: UTF8.self)
        XCTAssertTrue(cachedText.contains("ARRAY_STRING"))
        XCTAssertFalse(cachedText.contains("STRING_ARRAY"))
    }

    func testUndecodableSingleCampaignBecomesNil() throws {
        let json = "{\"code\":200,\"message\":\"ok\",\"data\":{\"campaign\":\(campaign(id: "x", op: "ANNIVERSARY_PAST"))}}"
        let response = try JSONDecoder().decode(ServerResponse<InAppCampaignSingleFetchResponse>.self, from: Data(json.utf8)).data

        XCTAssertNil(response.campaign)
    }

    func testMissingCampaignsStaysNil() throws {
        let json = "{\"code\":200,\"message\":\"ok\",\"data\":{\"checksum\":\"c\",\"campaigns\":null}}"
        let response = try JSONDecoder().decode(ServerResponse<InAppCampaignFetchResponse>.self, from: Data(json.utf8)).data

        XCTAssertNil(response.campaigns)
    }

    func testUnknownValuesInAbortAndFlowConditionsSkipOnlyThatCampaign() throws {
        let unknown = "{\"eventFilter\":{\"eventName\":\"e\"},\"propertyConditions\":[[{\"extractionStrategy\":{\"propertySchema\":{\"id\":\"\",\"name\":\"p\",\"dataType\":\"NEW_TYPE\",\"path\":\"EVENT\"}},\"operator\":\"EQUAL\",\"targetValues\":[\"a\"]}]]}"
        let trigger = "\"triggerEventCondition\":{"
        let response = try decodeList([
            campaign(id: "ok"),
            campaign(id: "abort").replacingOccurrences(of: trigger, with: "\(trigger)\"abortConditions\":[\(unknown)],"),
            campaign(id: "flow").replacingOccurrences(
                of: trigger,
                with: "\(trigger)\"flow\":{\"precedingSteps\":[{\"conditions\":[\(unknown)],\"withinSeconds\":60}]},"
            ),
        ])

        XCTAssertEqual(response.campaigns?.map { $0.id }, ["ok"])
    }

    func testUndecodableGlobalFrequencyCapLeavesCapsNil() throws {
        let caps = "[{\"limit\":3,\"durationMinutes\":60,\"tagIds\":[]},{\"durationMinutes\":60,\"tagIds\":[]}]"
        let json = "{\"code\":200,\"message\":\"ok\",\"data\":{\"checksum\":\"c\",\"campaigns\":[\(campaign(id: "ok"))],\"globalFrequencyCaps\":\(caps)}}"
        let response = try JSONDecoder().decode(ServerResponse<InAppCampaignFetchResponse>.self, from: Data(json.utf8)).data

        XCTAssertEqual(response.campaigns?.map { $0.id }, ["ok"])
        XCTAssertNil(response.globalFrequencyCaps)
    }

    func testDecodableGlobalFrequencyCapsAreKept() throws {
        let caps = "[{\"limit\":3,\"durationMinutes\":60,\"tagIds\":[]}]"
        let json = "{\"code\":200,\"message\":\"ok\",\"data\":{\"checksum\":\"c\",\"campaigns\":[\(campaign(id: "ok"))],\"globalFrequencyCaps\":\(caps)}}"
        let response = try JSONDecoder().decode(ServerResponse<InAppCampaignFetchResponse>.self, from: Data(json.utf8)).data

        XCTAssertEqual(response.globalFrequencyCaps, [GlobalFrequencyCapRule(limit: 3, durationMinutes: 60, tagIds: [])])
    }
}
