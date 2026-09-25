import XCTest

/// The repository's anonymisation rule, applied to the one committed file that is not corpus data.
///
/// `fixtures/` holds material captured from the Operator's live instance and anonymised by hand —
/// the transition graph M2's confirmation rule will be derived from (#15). `.gitignore` states the
/// rule that governs it ("this repository is public: … real instance config, and raw captures from
/// a live Jira belong on the local machine only (fixtures stay anonymised)"), and
/// `FixtureCorpusTests` enforces it for the corpus by walking `Bundle.module`'s `Fixtures`
/// directory. A hand-anonymised file outside that directory is exactly the case where an enforced
/// rule should not have to rely on somebody remembering.
///
/// So the checks are structural and name nothing: which instance the capture came from is itself
/// instance configuration, and writing its hostname into this file would put in the public
/// repository the very thing the test is there to keep out.
final class CommittedCaptureTests: XCTestCase {
    /// The repository root, from this file's own compiled-in path
    /// (`Tests/SprintPulseAppTests/CommittedCaptureTests.swift`).
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SprintPulseAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }

    private var committedCaptures: [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: repoRoot.appendingPathComponent("fixtures"),
            includingPropertiesForKeys: nil
        )) ?? [])
        .filter { $0.pathExtension == "json" }
        .sorted { $0.path < $1.path }
    }

    /// The corpus test's rule, and its reason. If either directory ever carries a real host, this
    /// repository has published the shape of somebody's Jira installation.
    func test_committedCaptures_nameOnlyExampleDomains() throws {
        XCTAssertFalse(
            committedCaptures.isEmpty,
            "#15 AC 8 asks for a committed capture, so an empty fixtures/ is a missing deliverable"
        )

        for file in committedCaptures {
            let text = try String(contentsOf: file, encoding: .utf8)

            let hosts = Self.urlHosts(in: text)
            for host in hosts where !Self.isExampleDomain(host) {
                XCTFail("\(file.lastPathComponent): names a real host — \(host)")
            }

            // Issue keys name projects, which is instance configuration too — the corpus writes
            // synthetic ones and so must this. Probed by shape rather than by prefix, because this
            // file cannot name the project it is guarding without putting it in the repository.
            let keys = Self.matches(of: #"\b[A-Z][A-Z0-9]{3,}-[0-9]+\b"#, in: text)
            XCTAssertTrue(
                keys.isEmpty,
                "\(file.lastPathComponent): contains what reads as a real Issue key — \(keys.prefix(2))"
            )

            // An address is the other thing a live capture arrives carrying.
            let emails = Self.emailAddresses(in: text)
            XCTAssertTrue(
                emails.isEmpty,
                "\(file.lastPathComponent): contains what reads as an email address — \(emails.prefix(2))"
            )
        }
    }

    /// The half the corpus test checks by requiring `@example.com` addresses: instance-authored
    /// free text. A Data Center status description on a Russian-hosted installation is written in
    /// Russian, so any character outside ASCII that is not one of the typographic marks this repo
    /// uses in its own prose means somebody pasted a capture rather than anonymised it.
    func test_committedCaptures_carryNoInstanceAuthoredProse() throws {
        let proseMarks: Set<Character> = ["—", "–", "’", "‘", "“", "”", "…", "×"]

        for file in committedCaptures {
            let text = try String(contentsOf: file, encoding: .utf8)
            let offenders = Set(text).filter {
                !$0.isASCII && !proseMarks.contains($0) && !$0.isNewline
            }
            XCTAssertTrue(
                offenders.isEmpty,
                "\(file.lastPathComponent): contains non-ASCII text outside this repo's own prose marks — \(offenders)"
            )
        }
    }

    /// AC 8's other half, checked rather than promised: the capture is *not used in this milestone*.
    /// Nothing under `Sources/` may reference it. M2 will decide what shape a reader takes, and an
    /// M1 code path quietly depending on it would make "unused" false in the one way that matters —
    /// a write path built on a graph this ticket was only meant to record.
    func test_committedCaptures_areReadByNothingInThisMilestone() throws {
        let sources = repoRoot.appendingPathComponent("Sources")
        let walked = try FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        let swiftFiles: [URL] = (walked?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(swiftFiles.isEmpty, "found no sources to scan, so this test checked nothing")

        for url in swiftFiles {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                text.contains("transition-graph") || text.contains("fixtures/"),
                "\(url.lastPathComponent) references the M2 capture — #15 says nothing in this milestone reads it"
            )
        }
    }

    // MARK: - Shape of the check

    private static func urlHosts(in text: String) -> [String] {
        matches(of: #"https?://([^/\s"',\\]+)"#, in: text).map {
            $0.components(separatedBy: "@").last ?? $0
        }
    }

    private static func emailAddresses(in text: String) -> [String] {
        matches(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: text)
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let scanner = try? NSRegularExpression(pattern: pattern) else { return [] }
        return scanner.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: $0.numberOfRanges > 1 ? 1 : 0), in: text).map { String(text[$0]) }
        }
    }

    /// The corpus test's allowlist, restated because that one is private to `FixtureCorpusTests` —
    /// the M0 file this ticket may not edit.
    private static func isExampleDomain(_ host: String) -> Bool {
        ["example.com", "example.org", "example.net", "example.invalid"]
            .contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
