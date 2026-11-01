struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        state = seed.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        let mixed = (state ^ (state >> 30)) &* 0xBF58_476D_1CE4_E5B9
        let spread = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return spread ^ (spread >> 31)
    }
}
