import Foundation
import Testing

@Test(arguments: [
    "https://github.com/gustaferiksson/crew/pull/42",
    "http://example.com/page?q=1",
    "HTTPS://Example.com",
    "https://archive-api.open-meteo.com/v1/archive?latitude=59.3293",
    "https://gustaferiksson.github.io/other",
    "https://gustaferiksson.github.io/crew/checkout-test.html",
])
func webLinksOpenInApp(_ link: String) throws {
    #expect(LinkDestination(try #require(URL(string: link))) == .inApp)
}

@Test(arguments: [
    "mailto:ada@example.com",
    "tel:+46701234567",
    "sms:+46701234567",
    "itms-services://?action=download-manifest&url=https://gustaferiksson.github.io/crew/manifest.plist",
    "https://gustaferiksson.github.io/crew/",
    "https://gustaferiksson.github.io/crew",
    "https://gustaferiksson.github.io/crew/index.html",
    "crew-mention:2",
    "maps://?q=Stockholm",
    "https:no-host",
    "file:///tmp/report.pdf",
])
func otherLinksGoToTheSystem(_ link: String) throws {
    #expect(LinkDestination(try #require(URL(string: link))) == .system)
}
