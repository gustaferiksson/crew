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
        ComponentImplementation(api: BasicCatalogComponents.card) { CrewCard(node: $0) },
        ComponentImplementation(api: BasicCatalogComponents.button) { CrewButton(node: $0) },
        ComponentImplementation(name: "Table", schema: tableSchema) { CrewTable(node: $0) },
        ComponentImplementation(name: "KeyValue", schema: keyValueSchema) { CrewKeyValue(node: $0) },
    ]
    let components = BasicCatalogImplementation.allComponents + crewComponents
    return [(crewCatalogID, A2UIProtocolVersion.v09), (V09BasicCatalog.catalogURI, .v09), (V09BasicCatalog.v091CatalogURI, .v091)].map { id, version in
        Catalog(id: id, protocolVersion: version, components: components, functions: V09BasicCatalog.functions, themeSchema: V09BasicCatalog.themeSchema)
    }
}()

private let tableSchema = try! Schema(instance: """
    {"type": "object", "required": ["component", "columns", "rows"], "properties": {
      "component": {"const": "Table"},
      "columns": {"type": "array", "items": {"type": "string"}},
      "rows": {"type": "array", "items": {"type": "array", "items": {"type": ["string", "number", "boolean"]}}}}}
    """)

private let keyValueSchema = try! Schema(instance: """
    {"type": "object", "required": ["component", "items"], "properties": {
      "component": {"const": "KeyValue"},
      "items": {"type": "array", "items": {"type": "object", "required": ["key", "value"], "properties": {
        "key": {"type": "string"}, "value": {"type": ["string", "number", "boolean"]}}}}}}
    """)
