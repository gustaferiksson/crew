import A2UICore
import JSONSchema
import OrderedJSON

nonisolated struct ScaleFunction: FunctionImplementation {
    let api = FunctionAPI(name: "scale", returnType: .string, schema: try! Schema(instance: """
        {"type": "object", "required": ["value", "from", "to"], "properties": {
          "value": {"type": "number"}, "from": {"type": "number"}, "to": {"type": "number"},
          "unit": {"type": "string"}, "item": {"type": "string"}, "one": {"type": "string"}}}
        """))

    func evaluate(arguments: [String: OrderedJSON.JSONValue], context: DataContext) throws -> OrderedJSON.JSONValue {
        let number = { (key: String) in arguments[key]?.doubleValue ?? arguments[key]?.stringValue.flatMap { Double($0) } }
        if let written = arguments["value"]?.stringValue, Double(written) == nil {
            return .string([written, arguments["unit"]?.stringValue ?? "", arguments["item"]?.stringValue ?? ""].filter { !$0.isEmpty }.joined(separator: " "))
        }
        return .string(scaledAmount(
            number("value"), from: number("from"), to: number("to"),
            unit: arguments["unit"]?.stringValue ?? "", item: arguments["item"]?.stringValue ?? "", one: arguments["one"]?.stringValue ?? ""
        ))
    }
}

nonisolated func scaledAmount(_ value: Double?, from: Double?, to: Double?, unit: String, item: String, one: String) -> String {
    let words = [unit, item].filter { !$0.isEmpty }.joined(separator: " ")
    guard let value, value.isFinite, value > 0 else { return words }

    let ratio = if let from, let to, from.isFinite, to.isFinite, from > 0, to > 0 { to / from } else { 1.0 }
    let amount = value * ratio
    guard value < 1_000_000_000, amount < 1_000_000_000 else { return words }

    let kind = unit.lowercased()
    let isCountable = ["", "st", "pcs"].contains(kind)
    let shown: Double
    if ratio == 1 {
        shown = value
    } else if ["g", "ml", "mg"].contains(kind) {
        let step: Double = amount < 20 ? 1 : amount < 500 ? 5 : amount < 1000 ? 10 : 50
        shown = max(1, (amount / step).rounded() * step)
    } else if amount >= (isCountable ? 2 : 10) {
        shown = amount.rounded()
    } else {
        let whole = amount.rounded(.down)
        let steps: [Double] = isCountable ? [0, 0.5, 1] : ["dl", "cup", "cups"].contains(kind) ? [0, 0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1] : [0, 0.25, 0.5, 0.75, 1]
        let nearest = steps.reversed().min { abs($0 - (amount - whole)) < abs($1 - (amount - whole)) } ?? 0
        shown = max(isCountable ? 0.5 : 0.25, whole + nearest)
    }

    let whole = Int((shown + 0.001).rounded(.down))
    let rest = shown - Double(whole)
    let glyph = [(0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾")].first { abs($0.0 - rest) < 0.01 }?.1
    let figure = if let glyph { (whole > 0 ? String(whole) : "") + glyph } else if rest < 0.001 { String(whole) } else { shown.formatted(.number.precision(.fractionLength(0...2))) }
    return [figure, shown <= 1 && !one.isEmpty ? one : words].filter { !$0.isEmpty }.joined(separator: " ")
}
