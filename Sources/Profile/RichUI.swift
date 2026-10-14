import Foundation

nonisolated private let richUIStart = "<!-- crew-ui:start -->"
nonisolated private let richUIEnd = "<!-- crew-ui:end -->"

nonisolated func splitRichUI(_ instructions: String) -> (instructions: String, richUI: Bool) {
    guard let start = instructions.range(of: richUIStart),
          let end = instructions.range(of: richUIEnd, range: start.upperBound..<instructions.endIndex)
    else { return (instructions, false) }
    let rest = instructions[..<start.lowerBound] + instructions[end.upperBound...]
    return (rest.trimmingCharacters(in: .whitespacesAndNewlines), true)
}

nonisolated func joinRichUI(_ instructions: String, richUI: Bool) -> String {
    guard richUI else { return instructions }
    return [instructions, "\(richUIStart)\n\(richUIRecipe)\n\(richUIEnd)"].filter { !$0.isEmpty }.joined(separator: "\n\n")
}

nonisolated let richUIApprovalExample = """
    [
      {"version": "v0.9", "createSurface": {"surfaceId": "cleanup-previews", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
      {"version": "v0.9", "updateComponents": {"surfaceId": "cleanup-previews", "components": [
        {"id": "root", "component": "Card", "child": "body"},
        {"id": "body", "component": "Column", "children": ["title", "detail", "actions"]},
        {"id": "title", "component": "Text", "text": "Delete 4 preview deployments?", "variant": "h4"},
        {"id": "detail", "component": "Text", "text": "pr-212, pr-218, pr-219 and pr-224 have been idle for over 14 days."},
        {"id": "actions", "component": "Row", "justify": "end", "children": ["keep", "delete"]},
        {"id": "keep-label", "component": "Text", "text": "Keep Them"},
        {"id": "keep", "component": "Button", "child": "keep-label", "action": {"event": {"name": "decide", "context": {"choice": "keep"}}}},
        {"id": "delete-label", "component": "Text", "text": "Delete"},
        {"id": "delete", "component": "Button", "child": "delete-label", "variant": "primary", "action": {"event": {"name": "decide", "context": {"choice": "delete"}}}}
      ]}}
    ]
    """

nonisolated let richUIRecipeExample = """
    [
      {"version": "v0.9", "createSurface": {"surfaceId": "tomato-soup", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
      {"version": "v0.9", "updateDataModel": {"surfaceId": "tomato-soup", "value": {"ingredients": [
        {"name": "1 kg ripe tomatoes", "done": false},
        {"name": "1 onion", "done": false},
        {"name": "2 cloves garlic", "done": false},
        {"name": "5 dl vegetable stock", "done": false}
      ]}}},
      {"version": "v0.9", "updateComponents": {"surfaceId": "tomato-soup", "components": [
        {"id": "root", "component": "Card", "child": "body"},
        {"id": "body", "component": "Column", "children": ["title", "meta", "list", "ready"]},
        {"id": "title", "component": "Text", "text": "Tomato Soup", "variant": "h3"},
        {"id": "meta", "component": "Text", "text": "4 servings · 40 min", "variant": "caption"},
        {"id": "list", "component": "Column", "children": {"componentId": "ingredient", "path": "/ingredients"}},
        {"id": "ingredient", "component": "CheckBox", "label": {"path": "name"}, "value": {"path": "done"}},
        {"id": "ready-label", "component": "Text", "text": "Start Cooking"},
        {"id": "ready", "component": "Button", "child": "ready-label", "variant": "primary", "action": {"event": {"name": "start_cooking", "context": {"ingredients": {"path": "/ingredients"}}}}}
      ]}}
    ]
    """

nonisolated let richUIFormExample = """
    [
      {"version": "v0.9", "createSurface": {"surfaceId": "booking", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
      {"version": "v0.9", "updateDataModel": {"surfaceId": "booking", "value": {"name": "", "date": "", "guests": ["2"], "notes": ""}}},
      {"version": "v0.9", "updateComponents": {"surfaceId": "booking", "components": [
        {"id": "root", "component": "Card", "child": "form"},
        {"id": "form", "component": "Column", "children": ["title", "name", "date", "guests", "notes", "submit"]},
        {"id": "title", "component": "Text", "text": "Table at Lilla Ego", "variant": "h4"},
        {"id": "name", "component": "TextField", "label": "Name on the booking", "value": {"path": "/name"}},
        {"id": "date", "component": "DateTimeInput", "label": "When", "value": {"path": "/date"}, "enableDate": true, "enableTime": true},
        {"id": "guests", "component": "ChoicePicker", "label": "Guests", "displayStyle": "chips", "value": {"path": "/guests"},
          "options": [{"label": "2", "value": "2"}, {"label": "4", "value": "4"}, {"label": "6", "value": "6"}]},
        {"id": "notes", "component": "TextField", "label": "Notes", "variant": "longText", "value": {"path": "/notes"}},
        {"id": "submit-label", "component": "Text", "text": "Request Booking"},
        {"id": "submit", "component": "Button", "child": "submit-label", "variant": "primary", "action": {"event": {"name": "book",
          "context": {"name": {"path": "/name"}, "date": {"path": "/date"}, "guests": {"path": "/guests"}, "notes": {"path": "/notes"}}}}}
      ]}}
    ]
    """

nonisolated private let richUIRecipe = """
    # Rich UI in Crew (managed by Crew's Rich UI switch; edit or remove it there)

    The Crew app draws A2UI v0.9 blocks as native cards. Use one when a reply offers a choice or decision, a list to tick off, a form to fill in, a recipe, or structured data such as a comparison table or key facts. Answer plainly when there is nothing to interact with or compare.

    Rules:
    - Write one or two lines of prose first and put the block last. Other apps show the block as code, so the prose must carry the answer on its own.
    - The block is one fenced code block with the language `a2ui`, holding a JSON array of messages. Every message has "version": "v0.9". Valid JSON only: no comments, no trailing commas. Keep it under 64 KB.
    - First message: {"version": "v0.9", "createSurface": {"surfaceId": "<new short id>", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}}. Use a fresh surfaceId for every new card.
    - Optional state for inputs: {"version": "v0.9", "updateDataModel": {"surfaceId": "<id>", "value": {...}}}.
    - Then {"version": "v0.9", "updateComponents": {"surfaceId": "<id>", "components": [...]}}: a flat list where exactly one component has "id": "root" and children are referenced by id, never nested inline.
    - {"path": "/a/b"} binds a property to the data model. Inside a template ({"componentId": "<id>", "path": "/items"}) paths are relative to the item, like {"path": "name"}.

    Components (exact property names):
    - Text: "text", "variant": "h1" | "h2" | "h3" | "h4" | "h5" | "body" | "caption"
    - Card: "child" (one id; wrap several in a Column)
    - Column, Row, List: "children" (array of ids, or a template); Row/Column "justify": "start" | "center" | "end" | "spaceBetween", "align": "start" | "center" | "end" | "stretch"
    - Divider
    - Image: "url" (https only), "description"
    - Icon: "name", one of check, close, info, warning, star, favorite, event, locationOn, shoppingCart, mail, phone, home, person, settings
    - Button: "child" (id of a Text label), "variant": "default" | "primary" | "borderless", "action": {"event": {"name": "<name>", "context": {"<key>": <literal or {"path": ...}>}}}
    - CheckBox: "label", "value" (bound boolean)
    - TextField: "label", "value" (bound string), "variant": "shortText" | "longText" | "number" | "obscured"
    - ChoicePicker: "label", "options": [{"label": "...", "value": "..."}], "value" (bound array of strings), "variant": "mutuallyExclusive" | "multipleSelection", "displayStyle": "checkbox" | "chips"
    - DateTimeInput: "label", "value" (bound ISO 8601 string, "" when unset), "enableDate", "enableTime"
    - Slider: "label", "min", "max", "value" (bound number)
    - Table (Crew only): "columns": ["..."], "rows": [["...", ...], ...], every cell a string
    - KeyValue (Crew only): "items": [{"key": "...", "value": "..."}], strings only

    When the user taps a button, Crew sends you a hidden message like
    <a2ui-action>{"context": {"choice": "delete"}, "name": "decide", "sourceComponentId": "delete", "surfaceId": "cleanup-previews"}</a2ui-action>
    with the bound values resolved at tap time. Crew already marks the tapped button, so reply briefly in prose and act on it. To change the card instead, send a block with updateComponents or updateDataModel for the same surfaceId and no createSurface.

    Example, a decision:
    ```a2ui
    \(richUIApprovalExample)
    ```

    Example, a recipe with an ingredient checklist:
    ```a2ui
    \(richUIRecipeExample)
    ```

    Example, a form:
    ```a2ui
    \(richUIFormExample)
    ```
    """
