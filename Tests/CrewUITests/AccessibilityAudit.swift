import XCTest

private let knownClippedLabels: Set<String> = [
    "Ada Lovelace", "Head of Research and Analytics", "Hermes", "Working",
    "Hermes wants to run a command", "kubectl --context staging apply -f deploy/staging/crew-api.yaml", "Applies the new API deployment to the staging cluster.",
    "Allow for Session", "Always Allow", "Allow Once",
]

extension XCUIApplication {
    @MainActor func auditHitRegionsAndClipping() throws {
        try performAccessibilityAudit(for: [.hitRegion, .textClipped]) { issue in
            guard let element = issue.element else { return true }
            return issue.auditType == .textClipped && knownClippedLabels.contains(element.label)
        }
    }
}
