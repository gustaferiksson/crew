import Foundation

nonisolated func isNewerVersion(_ remote: String, than local: String) -> Bool {
    let components = { (version: String) in
        (version.hasPrefix("v") ? String(version.dropFirst()) : version).split(separator: ".").map { Int($0) ?? 0 }
    }
    let r = components(remote), l = components(local)
    for index in 0..<max(r.count, l.count) {
        let a = index < r.count ? r[index] : 0, b = index < l.count ? l[index] : 0
        if a != b { return a > b }
    }
    return false
}
