import XCTest
import Carbon.HIToolbox
@testable import lanes

@MainActor
final class GlobalCaptureShortcutTests: XCTestCase {
    func testOptionQIsTheConfiguredShortcut() {
        XCTAssertEqual(GlobalShortcutEvent.optionQ.keyCode, UInt32(kVK_ANSI_Q))
        XCTAssertEqual(GlobalShortcutEvent.optionQ.modifiers, optionKeyValue)
    }

    func testOptionLIsThePanelShortcut() {
        XCTAssertEqual(GlobalShortcutEvent.optionL.keyCode, UInt32(kVK_ANSI_L))
        XCTAssertEqual(GlobalShortcutEvent.optionL.modifiers, optionKeyValue)
    }

    func testCarbonRoutingConsumesOnlyTheMatchingShortcutEvent() {
        XCTAssertTrue(CarbonGlobalShortcutRouting.shouldHandle(
            signature: CarbonGlobalShortcutRouting.signature,
            id: GlobalShortcutEvent.optionL.keyCode,
            registeredID: GlobalShortcutEvent.optionL.keyCode
        ))
        XCTAssertFalse(CarbonGlobalShortcutRouting.shouldHandle(
            signature: CarbonGlobalShortcutRouting.signature,
            id: GlobalShortcutEvent.optionL.keyCode,
            registeredID: GlobalShortcutEvent.optionQ.keyCode
        ))
    }

    func testParserAcceptsOptionLAndOptionQAndRejectsOtherModifierCombinations() {
        XCTAssertEqual(GlobalShortcutParser.parse(keyCode: UInt16(kVK_ANSI_L), modifierFlags: [.option]), .optionL)
        XCTAssertEqual(GlobalShortcutParser.parse(keyCode: UInt16(kVK_ANSI_Q), modifierFlags: [.option]), .optionQ)
        XCTAssertNil(GlobalShortcutParser.parse(keyCode: UInt16(kVK_ANSI_Q), modifierFlags: [.option, .command]))
        XCTAssertNil(GlobalShortcutParser.parse(keyCode: 36, modifierFlags: [.option]))
        XCTAssertNil(GlobalShortcutParser.parse(keyCode: UInt16(kVK_ANSI_Q), modifierFlags: []))
    }

    func testRegistrationIsIdempotentAndRoutesMatchingEvent() {
        let registrar = FakeRegistrar()
        var actionCount = 0
        let controller = GlobalCaptureShortcutController(registrar: registrar) { actionCount += 1 }

        XCTAssertTrue(controller.register())
        XCTAssertTrue(controller.register())
        XCTAssertEqual(registrar.registerCount, 1)
        controller.route(.optionQ)
        XCTAssertEqual(actionCount, 1)
    }

    func testNonMatchingEventDoesNotRoute() {
        let registrar = FakeRegistrar()
        var actionCount = 0
        let controller = GlobalCaptureShortcutController(registrar: registrar) { actionCount += 1 }
        XCTAssertTrue(controller.register())

        controller.route(GlobalShortcutEvent(keyCode: 36, modifiers: GlobalShortcutEvent.optionQ.modifiers))
        controller.route(GlobalShortcutEvent(keyCode: GlobalShortcutEvent.optionQ.keyCode, modifiers: 0))
        XCTAssertEqual(actionCount, 0)
    }

    func testFailedRegistrationPreservesIdleStateAndCanBeCleanedUp() {
        let registrar = FakeRegistrar(result: false)
        let controller = GlobalCaptureShortcutController(registrar: registrar) {}

        XCTAssertFalse(controller.register())
        XCTAssertEqual(controller.state, .failed)
        controller.unregister()
        XCTAssertEqual(registrar.unregisterCount, 0)
    }

    func testUnregisterIsSafeAndStopsRouting() {
        let registrar = FakeRegistrar()
        var actionCount = 0
        let controller = GlobalCaptureShortcutController(registrar: registrar) { actionCount += 1 }
        XCTAssertTrue(controller.register())
        controller.unregister()
        controller.unregister()
        controller.route(.optionQ)

        XCTAssertEqual(actionCount, 0)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(registrar.unregisterCount, 1)
    }

    private var optionKeyValue: UInt32 { UInt32(optionKey) }
}

private final class FakeRegistrar: GlobalShortcutRegistering {
    var result: Bool
    var registerCount = 0
    var unregisterCount = 0
    private var handler: (() -> Void)?

    init(result: Bool = true) { self.result = result }

    func register(_ shortcut: GlobalShortcutEvent, handler: @escaping () -> Void) -> Bool {
        registerCount += 1
        guard result else { return false }
        self.handler = handler
        return true
    }

    func unregister() {
        unregisterCount += 1
        handler = nil
    }
}
