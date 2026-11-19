import XCTest
@testable import MarketapSDK

private struct EventFlowCases: Decodable {
    struct FlowSpec: Decodable {
        struct Step: Decodable {
            let events: [String]
            let withinSeconds: Int
        }
        let steps: [Step]
        let arrival: [String]
        let cancel: [String]
        let reentryBlockSeconds: Int?
    }
    struct Expect: Decodable {
        struct State: Decodable {
            let nextStep: Int
            let lastStepAt: Int64
            let blockedUntil: Int64?
        }
        let fired: Bool
        let restarted: Bool
        let state: State?
    }
    struct Input: Decodable {
        let event: String?
        let at: Int64?
        let impression: Bool?
        let expect: Expect?
    }
    struct Case: Decodable {
        let name: String
        let flow: FlowSpec
        let inputs: [Input]
    }
    let cases: [Case]
}

private func condition(_ eventName: String) -> Condition {
    Condition(eventFilter: EventFilter(eventName: eventName), propertyConditions: nil)
}

final class EventFlowRuleContractTests: XCTestCase {
    private func loadCases() throws -> [EventFlowCases.Case] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "event-flow-cases", withExtension: "json"))
        return try JSONDecoder().decode(EventFlowCases.self, from: Data(contentsOf: url)).cases
    }

    func testCaseCountMatchesSharedContract() throws {
        XCTAssertEqual(try loadCases().count, 26)
    }

    func testAllSharedCases() throws {
        var checkedInputs = 0
        for flowCase in try loadCases() {
            let flow = EventFlow(
                precedingSteps: flowCase.flow.steps.map {
                    EventFlowStep(conditions: $0.events.map(condition), withinSeconds: $0.withinSeconds)
                },
                reentryBlockSeconds: flowCase.flow.reentryBlockSeconds
            )
            let cancelConditions = flowCase.flow.cancel.map(condition)
            var state: EventFlowState?

            for (index, input) in flowCase.inputs.enumerated() {
                if input.impression == true {
                    state = nil
                    continue
                }
                let eventName = try XCTUnwrap(input.event)
                let transition = EventFlowRule.next(
                    state: state,
                    flow: flow,
                    arrivalMatched: flowCase.flow.arrival.contains(eventName),
                    cancelConditions: cancelConditions,
                    eventAt: try XCTUnwrap(input.at) * 1000,
                    matches: { $0.eventFilter.eventName == eventName }
                )
                let expected = try XCTUnwrap(input.expect)
                let expectedState = expected.state.map {
                    EventFlowState(
                        nextStep: $0.nextStep,
                        lastStepAt: $0.lastStepAt * 1000,
                        blockedUntil: $0.blockedUntil.map { $0 * 1000 }
                    )
                }
                let label = "\(flowCase.name) #\(index)"
                XCTAssertEqual(transition.fired, expected.fired, label)
                XCTAssertEqual(transition.restarted, expected.restarted, label)
                XCTAssertEqual(transition.state, expectedState, label)
                state = transition.state
                checkedInputs += 1
            }
        }
        XCTAssertGreaterThan(checkedInputs, 26)
    }
}

final class EventFlowDecodingTests: XCTestCase {
    private func decode(_ trigger: String) throws -> InAppCampaign {
        let json = """
        {"id":"a","layout":{"layoutType":"MODAL","layoutSubType":"CENTER","orientations":["portrait"]},
         "triggerEventCondition":\(trigger),"html":null,"updatedAt":"2026-11-19T00:00:00Z"}
        """
        return try JSONDecoder().decode(InAppCampaign.self, from: Data(json.utf8))
    }

    func testREG2_DecodesWithoutFlow() throws {
        let campaign = try decode(#"{"condition":{"eventFilter":{"eventName":"view"}}}"#)
        XCTAssertNil(campaign.triggerEventCondition.flow)
        XCTAssertFalse(campaign.triggerEventCondition.hasEventFlow)
    }

    func testREG2_DecodesWithFlow() throws {
        let campaign = try decode("""
        {"condition":{"eventFilter":{"eventName":"view"}},
         "flow":{"precedingSteps":[{"conditions":[{"eventFilter":{"eventName":"signup"}}],"withinSeconds":1800}],
                 "reentryBlockSeconds":3600}}
        """)
        let flow = try XCTUnwrap(campaign.triggerEventCondition.flow)
        XCTAssertEqual(flow.precedingSteps.first?.conditions.first?.eventFilter.eventName, "signup")
        XCTAssertEqual(flow.precedingSteps.first?.withinSeconds, 1800)
        XCTAssertEqual(flow.reentryBlockSeconds, 3600)
        XCTAssertTrue(campaign.triggerEventCondition.hasEventFlow)
    }

    func testREG2_DecodesFlowWithoutReentryBlock() throws {
        let campaign = try decode("""
        {"condition":{"eventFilter":{"eventName":"view"}},
         "flow":{"precedingSteps":[{"conditions":[{"eventFilter":{"eventName":"signup"}}],"withinSeconds":60}]}}
        """)
        XCTAssertNil(campaign.triggerEventCondition.flow?.reentryBlockSeconds)
    }
}
