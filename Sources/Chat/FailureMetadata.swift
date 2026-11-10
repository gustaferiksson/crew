import Foundation

nonisolated struct FailureMetadata: Decodable, Sendable {
    let error: String?
    let errorSurface: LimitFailure.Surface?

    private enum CodingKeys: CodingKey {
        case error, errorSurface
    }

    init(from decoder: any Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        error = try? container?.decodeIfPresent(String.self, forKey: .error)
        errorSurface = try? container?.decodeIfPresent(LimitFailure.Surface.self, forKey: .errorSurface)
    }
}
