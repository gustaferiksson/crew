import Testing

struct SystemSymbolTests {
    @Test func anA2UIIconNameIsNotDrawnAsASymbol() {
        #expect(systemSymbol("shoppingCart") == nil)
        #expect(systemSymbol(nil) == nil)
    }

    @Test func anSFSymbolNameIsKept() {
        #expect(systemSymbol("bag.fill") == "bag.fill")
    }
}
