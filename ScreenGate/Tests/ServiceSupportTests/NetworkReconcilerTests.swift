import XCTest
import ServiceSupport

private enum NetworkFailure: Error { case journal, commit, apply, set }
private final class FakeNetwork {
    var preferences: [String: Bool]
    var active: [String: Bool]
    var events: [String] = []
    var failCommit = false
    var failApply = false
    var failSet: String?
    init(_ values: [String: Bool]) { preferences = values; active = values }
    final class Session: NetworkPreferencesSession {
        let network: FakeNetwork
        var working: [String: Bool]
        init(_ network: FakeNetwork) { self.network = network; working = network.preferences }
        func services() throws -> [NetworkServiceSnapshot] {
            working.keys.sorted().map { NetworkServiceSnapshot(id: $0, enabled: working[$0]!) }
        }
        func setEnabled(_ enabled: Bool, for id: String) throws {
            network.events.append("set:\(id):\(enabled)")
            if network.failSet == id { throw NetworkFailure.set }
            working[id] = enabled
        }
        func commit() throws {
            network.events.append("commit")
            if network.failCommit { throw NetworkFailure.commit }
            network.preferences = working
        }
        func apply() throws {
            network.events.append("apply")
            if network.failApply { throw NetworkFailure.apply }
            network.active = network.preferences
        }
    }
}

final class NetworkReconcilerTests: XCTestCase {
    func testStableBlockHasNoRepeatedApplyCommitOrJournalWrites() throws {
        let network = FakeNetwork(["wifi": true, "ethernet": false])
        let reconciler = NetworkReconciler()
        var journal: [String] = [], durable: [String] = []
        func run() throws -> Bool {
            try reconciler.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) {
                network.events.append("journal"); durable = $0
            }
        }
        XCTAssertTrue(try run())
        XCTAssertEqual(network.events, ["journal", "set:wifi:false", "commit", "apply"])
        XCTAssertEqual(durable, ["wifi"])
        XCTAssertEqual(network.active["wifi"], false)
        network.events.removeAll()
        for _ in 0..<720 { XCTAssertTrue(try run()) } // One hour of five-second inspections.
        XCTAssertTrue(network.events.isEmpty)
    }
    func testNewlyEnabledServiceIsJournaledBeforeItIsDisabled() throws {
        let network = FakeNetwork(["wifi": false, "usb": true])
        let reconciler = NetworkReconciler()
        var journal = ["wifi"]
        XCTAssertTrue(try reconciler.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) { ids in
            network.events.append("journal")
            XCTAssertEqual(Set(ids), ["wifi", "usb"])
            XCTAssertEqual(network.active["usb"], true)
        })
        XCTAssertEqual(network.events, ["journal", "set:usb:false", "commit", "apply"])
        XCTAssertEqual(network.active["usb"], false)
    }
    func testFailedJournalSavePreventsAnyNetworkChange() throws {
        let network = FakeNetwork(["wifi": true])
        let reconciler = NetworkReconciler()
        var journal: [String] = []
        XCTAssertThrowsError(try reconciler.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in
            throw NetworkFailure.journal
        })
        XCTAssertTrue(network.events.isEmpty)
        XCTAssertEqual(network.active["wifi"], true)
        XCTAssertTrue(try reconciler.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in
            network.events.append("journal")
        })
        XCTAssertEqual(network.events.first, "journal")
        XCTAssertEqual(network.active["wifi"], false)
    }
    func testFailedApplyRetriesOnceThenStableChecksDoNothing() throws {
        let network = FakeNetwork(["wifi": true])
        let reconciler = NetworkReconciler()
        var journal: [String] = []
        network.failApply = true
        XCTAssertThrowsError(try reconciler.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in })
        XCTAssertTrue(reconciler.hasPendingApply)
        XCTAssertEqual(network.preferences["wifi"], false)
        XCTAssertEqual(network.active["wifi"], true)
        network.failApply = false; network.events.removeAll()
        XCTAssertTrue(try reconciler.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in })
        XCTAssertEqual(network.events, ["apply"])
        XCTAssertFalse(reconciler.hasPendingApply)
        network.events.removeAll()
        _ = try reconciler.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in }
        XCTAssertTrue(network.events.isEmpty)
    }
    func testFailedCommitAndPartialSetCanBeRetriedWithJournalIntact() throws {
        for failure in ["commit", "set"] {
            let network = FakeNetwork(["a": true, "b": true])
            network.failCommit = failure == "commit"
            network.failSet = failure == "set" ? "b" : nil
            let reconciler = NetworkReconciler()
            var journal: [String] = [], durable: [String] = []
            XCTAssertThrowsError(try reconciler.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) { durable = $0 })
            XCTAssertEqual(Set(durable), ["a", "b"])
            XCTAssertEqual(network.active, ["a": true, "b": true])
            network.failCommit = false; network.failSet = nil
            XCTAssertTrue(try reconciler.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) { durable = $0 })
            XCTAssertEqual(network.active, ["a": false, "b": false])
        }
    }
    func testPauseRestoresOnlyJournaledServicesAndClearsJournalAfterApply() throws {
        let network = FakeNetwork(["wifi": false, "ethernet": false])
        let reconciler = NetworkReconciler(recoveringJournal: true)
        var journal = ["wifi"]
        XCTAssertFalse(try reconciler.reconcile(block: false, session: FakeNetwork.Session(network), restoreIDs: &journal) { ids in
            XCTAssertEqual(network.active["wifi"], true)
            XCTAssertTrue(ids.isEmpty)
            network.events.append("clear-journal")
        })
        XCTAssertEqual(network.events, ["set:wifi:true", "commit", "apply", "clear-journal"])
        XCTAssertEqual(network.active["ethernet"], false)
        XCTAssertTrue(journal.isEmpty)
        network.events.removeAll()
        _ = try reconciler.reconcile(block: false, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in XCTFail() }
        XCTAssertTrue(network.events.isEmpty)
    }
    func testRestorationApplyFailureKeepsJournalAcrossRetryOrRestart() throws {
        let network = FakeNetwork(["wifi": false])
        let reconciler = NetworkReconciler(recoveringJournal: true)
        var journal = ["wifi"]
        network.failApply = true
        XCTAssertThrowsError(try reconciler.reconcile(block: false, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in XCTFail("Cleared before apply") })
        XCTAssertEqual(journal, ["wifi"])
        XCTAssertEqual(network.preferences["wifi"], true)
        XCTAssertEqual(network.active["wifi"], false)
        network.failApply = false; network.events.removeAll()
        let restarted = NetworkReconciler(recoveringJournal: true)
        _ = try restarted.reconcile(block: false, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in network.events.append("clear") }
        XCTAssertEqual(network.events, ["apply", "clear"])
        XCTAssertEqual(network.active["wifi"], true)
        XCTAssertTrue(journal.isEmpty)
    }
    func testFailedJournalClearDoesNotCauseRepeatedSuccessfulApply() throws {
        let network = FakeNetwork(["wifi": false])
        let reconciler = NetworkReconciler(recoveringJournal: true)
        var journal = ["wifi"]
        XCTAssertThrowsError(try reconciler.reconcile(block: false, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in throw NetworkFailure.journal })
        XCTAssertEqual(journal, ["wifi"])
        network.events.removeAll()
        _ = try reconciler.reconcile(block: false, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in network.events.append("clear") }
        XCTAssertEqual(network.events, ["clear"])
        XCTAssertTrue(journal.isEmpty)
    }
    func testRestartReappliesPendingRestrictionOnce() throws {
        let network = FakeNetwork(["wifi": false])
        let restarted = NetworkReconciler(recoveringJournal: true)
        var journal = ["wifi"]
        _ = try restarted.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in XCTFail() }
        XCTAssertEqual(network.events, ["apply"])
        network.events.removeAll()
        _ = try restarted.reconcile(block: true, session: FakeNetwork.Session(network), restoreIDs: &journal) { _ in XCTFail() }
        XCTAssertTrue(network.events.isEmpty)
    }
}
