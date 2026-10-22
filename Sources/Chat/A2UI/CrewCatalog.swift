import A2UICore
import A2UISwiftUI
import BasicCatalog
import BasicCatalogSwiftUI
import JSONSchema
import SwiftUI

let crewCatalogID = "https://crew.gustaf.dev/catalogs/crew/v1.json"

let crewCatalogs: [Catalog<ComponentImplementation>] = {
    let crewComponents = [
        ComponentImplementation(api: BasicCatalogComponents.text) { CrewText(node: $0) },
        ComponentImplementation(api: BasicCatalogComponents.column) { CrewColumn(node: $0) },
        ComponentImplementation(api: BasicCatalogComponents.card) { CrewCard(node: $0) },
        ComponentImplementation(api: BasicCatalogComponents.button) { CrewButton(node: $0) },
        ComponentImplementation(api: BasicCatalogComponents.checkBox) { CrewCheckBox(node: $0) },
        ComponentImplementation(api: BasicCatalogComponents.choicePicker) { CrewChoicePicker(node: $0) },
        ComponentImplementation(api: BasicCatalogComponents.textField) { CrewTextField(node: $0) },
        ComponentImplementation(api: BasicCatalogComponents.dateTimeInput) { CrewDateTimeInput(node: $0) },
        ComponentImplementation(name: "Header", schema: crewSchema("Header", required: ["title"], properties: """
            "title": {"type": "string"}, "subtitle": {"type": "string"}, "symbol": {"type": "string"},
            "image": {"type": "string"}, "tone": \(toneSchema)
            """)) { CrewHeader(node: $0) },
        ComponentImplementation(name: "Steps", schema: crewSchema("Steps", required: ["items"], properties: """
            "items": {"type": "array", "items": {"type": "string"}}
            """)) { CrewSteps(node: $0) },
        ComponentImplementation(name: "Badge", schema: crewSchema("Badge", required: ["text"], properties: """
            "text": {"type": "string"}, "symbol": {"type": "string"}, "tone": \(toneSchema)
            """)) { CrewBadge(node: $0) },
        ComponentImplementation(name: "Table", schema: crewSchema("Table", required: ["columns", "rows"], properties: """
            "columns": {"type": "array", "items": {"type": "string"}},
            "rows": {"type": "array", "items": {"type": "array", "items": {"type": "string"}}}
            """)) { CrewTable(node: $0) },
        ComponentImplementation(name: "KeyValue", schema: crewSchema("KeyValue", required: ["items"], properties: """
            "items": {"type": "array", "items": {"type": "object", "required": ["key", "value"], "properties": {
              "key": {"type": "string"}, "value": {"type": "string"}, "symbol": {"type": "string"}}}}
            """)) { CrewKeyValue(node: $0) },
        ComponentImplementation(name: "Chart", schema: crewSchema("Chart", required: ["labels"], properties: """
            "kind": {"enum": ["bar", "line", "area"]}, "unit": {"type": "string"},
            "labels": {"type": "array", "items": {"type": "string"}},
            "values": {"type": "array", "items": {"type": "number"}},
            "series": {"type": "array", "items": {"type": "object", "required": ["name", "values"], "properties": {
              "name": {"type": "string"}, "values": {"type": "array", "items": {"type": "number"}}}}}
            """)) { CrewChart(node: $0) },
        ComponentImplementation(name: "Map", schema: crewSchema("Map", required: ["markers"], properties: """
            "markers": {"type": "array", "items": {"type": "object", "required": ["title", "latitude", "longitude"], "properties": {
              "title": {"type": "string"}, "latitude": {"type": "number"}, "longitude": {"type": "number"}}}},
            "region": {"type": "object", "required": ["latitude", "longitude"], "properties": {
              "latitude": {"type": "number"}, "longitude": {"type": "number"}, "span": {"type": "number"}}}
            """)) { CrewMap(node: $0) },
        ComponentImplementation(name: "Carousel", schema: crewSchema("Carousel", required: ["items"], properties: """
            "items": {"type": "array", "items": {"type": "object", "required": ["title"], "properties": {
              "title": {"type": "string"}, "subtitle": {"type": "string"}, "price": {"type": "string"}, "badge": {"type": "string"},
              "tone": \(toneSchema), "image": {"type": "string"}, "url": {"type": "string"}, "text": {"type": "string"}}}}
            """)) { CrewCarousel(node: $0) },
    ]
    let components = BasicCatalogImplementation.allComponents + crewComponents
    return [(crewCatalogID, A2UIProtocolVersion.v09), (V09BasicCatalog.catalogURI, .v09), (V09BasicCatalog.v091CatalogURI, .v091)].map { id, version in
        Catalog(id: id, protocolVersion: version, components: components, functions: V09BasicCatalog.functions, themeSchema: V09BasicCatalog.themeSchema)
    }
}()

private let toneSchema = #"{"enum": ["neutral", "info", "success", "warning", "critical", "accent"]}"#

private func crewSchema(_ name: String, required: [String], properties: String) -> Schema {
    try! Schema(instance: """
        {"type": "object", "required": ["component", \(required.map { "\"\($0)\"" }.joined(separator: ", "))], "properties": {
          "component": {"const": "\(name)"}, \(properties)}}
        """)
}
