import Testing
@testable import Burrito

@Suite("Update versions")
struct BurritoUpdateManagerTests {
    @Test("Accepts release tags with or without a v prefix")
    func acceptsReleaseTags() throws {
        let plain = try #require(BurritoReleaseVersion("1.2.3"))
        let prefixed = try #require(BurritoReleaseVersion("v1.2.3"))

        #expect(plain == prefixed)
        #expect(plain.description == "1.2.3")
    }

    @Test("Compares versions numerically and pads missing components")
    func comparesNumerically() throws {
        let one = try #require(BurritoReleaseVersion("1"))
        let oneZero = try #require(BurritoReleaseVersion("1.0"))
        let oneNine = try #require(BurritoReleaseVersion("1.9"))
        let oneTen = try #require(BurritoReleaseVersion("1.10"))

        #expect(one == oneZero)
        #expect(oneNine < oneTen)
    }

    @Test(
        "Rejects malformed release tags",
        arguments: ["", "release-1.0", "1..0", "1.0.0.1", "1.0-beta"]
    )
    func rejectsMalformedTags(_ value: String) {
        #expect(BurritoReleaseVersion(value) == nil)
    }
}
