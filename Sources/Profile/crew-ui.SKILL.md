---
name: crew-ui
description: Use for checklists, tables, charts, maps, forms and cards.
version: 5
---

# Rich UI in Crew

Installed by the Crew app's Rich UI switch. Crew replaces this file when it ships a newer `version`; bump the version here only if you want your edits to survive.

The Crew app draws A2UI v0.9 blocks as native cards. Use one when a reply offers a choice or decision, a list to tick off, a form to fill in, a recipe or how-to, structured data such as a comparison table or key facts, numbers over time or categories (a chart), or places (a map). Answer plainly when there is nothing to interact with or compare.

Rules:
- Write one or two lines of prose first and put the block last. Other apps show the block as code, so the prose must carry the answer on its own.
- The block is one fenced code block with the language `a2ui`, holding a JSON array of messages. Every message has "version": "v0.9". Valid JSON only: no comments, no trailing commas. Keep it under 64 KB.
- First message: {"version": "v0.9", "createSurface": {"surfaceId": "<new short id>", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}}. Use a fresh surfaceId for every new card.
- Optional state for inputs: {"version": "v0.9", "updateDataModel": {"surfaceId": "<id>", "value": {...}}}.
- Then {"version": "v0.9", "updateComponents": {"surfaceId": "<id>", "components": [...]}}: a flat list where exactly one component has "id": "root" and children are referenced by id, never nested inline.
- The root is always a Card whose child is a Column that starts with a Header. Never use a bare Column as the root, and never skip the Header.
- {"path": "/a/b"} binds a property to the data model. Inside a template ({"componentId": "<id>", "path": "/items"}) paths are relative to the item, like {"path": "name"}.

Components (exact property names):
- Text: "text" (inline markdown), "variant": "h1" | "h2" | "h3" | "h4" | "h5" | "body" | "caption". Use h4 for section titles inside a card, caption for fine print.
- Card: "child" (one id; wrap several in a Column). Make it the root: Crew draws the root as the card, so never nest a Card inside another.
- Column, Row, List: "children" (array of ids, or a template); Row/Column "justify": "start" | "center" | "end" | "spaceBetween", "align": "start" | "center" | "end" | "stretch"
- Divider
- Image: "url" (https only), "description"
- Icon: "name", one of check, close, info, warning, star, favorite, event, locationOn, shoppingCart, mail, phone, home, person, settings
- Button: "child" (id of a Text label), "variant": "default" | "primary" | "borderless", "action": {"event": {"name": "<name>", "context": {"<key>": <literal or {"path": ...}>}}}. One primary button per card, for the main action.
- CheckBox: "label", "value" (bound boolean). Ticked rows strike through, so use them for ingredients, packing lists and to-dos.
- TextField: "label", "value" (bound string), "variant": "shortText" | "longText" | "number" | "obscured"
- ChoicePicker: "label", "options": [{"label": "...", "value": "..."}], "value" (bound array of strings), "variant": "mutuallyExclusive" | "multipleSelection", "displayStyle": "checkbox" | "chips"
- DateTimeInput: "label", "value" (bound ISO 8601 string, "" when unset), "enableDate", "enableTime"
- Slider: "label", "min", "max", "value" (bound number)

Crew-only components (plain values, no {"path"} bindings):
- Header: "title", "subtitle" (meta line, e.g. "4 servings · 40 min"), "symbol" (an SF Symbol name such as "fork.knife", "airplane", "cloud.sun.fill", "cup.and.saucer.fill", "trash"), "image" (https hero photo), "tone": "accent" | "info" | "success" | "warning" | "critical". Start every card with one instead of a Text title.
- Steps: "items": ["...", ...], numbered method steps (no "1." prefixes in the strings)
- Badge: "text", "tone": "neutral" | "info" | "success" | "warning" | "critical", optional "symbol". Short status like "Cheapest", "Idle 14 days"; put several in a Row.
- Table: "columns": ["..."], "rows": [["...", ...], ...], every cell a string; columns whose cells start with a digit align right
- KeyValue: "items": [{"key": "...", "value": "...", "symbol": "<optional SF Symbol>"}], strings only; for key facts like a settings list (keep values short, long ones stack under the key)
- Chart: "kind": "bar" | "line" | "area", "labels": ["Mon", ...], and either "values": [numbers] or "series": [{"name": "High", "values": [numbers]}, ...] for several lines or bar groups, optional "unit" (e.g. "°C"). One value per label.
- Map: "markers": [{"title": "...", "latitude": 59.31, "longitude": 18.07}], optional "region": {"latitude": ..., "longitude": ..., "span": <degrees, 0.02 is a neighbourhood>}; without a region it fits all markers. Use real coordinates only.

When the user taps a button, Crew sends you a hidden message like
<a2ui-action>{"context": {"choice": "delete"}, "name": "decide", "sourceComponentId": "delete", "surfaceId": "cleanup-previews"}</a2ui-action>
with the bound values resolved at tap time. Crew already marks the tapped button, so reply briefly in prose and act on it. To change the card instead, send a block with updateComponents or updateDataModel for the same surfaceId and no createSurface.

Example, a decision:
```a2ui
[
  {"version": "v0.9", "createSurface": {"surfaceId": "cleanup-previews", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
  {"version": "v0.9", "updateComponents": {"surfaceId": "cleanup-previews", "components": [
    {"id": "root", "component": "Card", "child": "body"},
    {"id": "body", "component": "Column", "children": ["header", "detail", "badges", "actions"]},
    {"id": "header", "component": "Header", "title": "Delete 4 preview deployments?", "subtitle": "crew-web on Vercel", "symbol": "trash", "tone": "critical"},
    {"id": "detail", "component": "Text", "text": "pr-212, pr-218, pr-219 and pr-224 have had no traffic since September."},
    {"id": "badges", "component": "Row", "children": ["idle", "cost"]},
    {"id": "idle", "component": "Badge", "text": "Idle 14+ days", "tone": "warning", "symbol": "clock"},
    {"id": "cost", "component": "Badge", "text": "Frees 4 slots", "tone": "success"},
    {"id": "actions", "component": "Row", "justify": "end", "children": ["keep", "delete"]},
    {"id": "keep-label", "component": "Text", "text": "Keep Them"},
    {"id": "keep", "component": "Button", "child": "keep-label", "action": {"event": {"name": "decide", "context": {"choice": "keep"}}}},
    {"id": "delete-label", "component": "Text", "text": "Delete"},
    {"id": "delete", "component": "Button", "child": "delete-label", "variant": "primary", "action": {"event": {"name": "decide", "context": {"choice": "delete"}}}}
  ]}}
]
```

Example, a recipe with an ingredient checklist and method:
```a2ui
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
    {"id": "body", "component": "Column", "children": ["header", "ingredients-title", "list", "method-title", "method"]},
    {"id": "header", "component": "Header", "title": "Tomato Soup", "subtitle": "4 servings · 40 min", "symbol": "fork.knife"},
    {"id": "ingredients-title", "component": "Text", "text": "Ingredients", "variant": "h4"},
    {"id": "list", "component": "Column", "children": {"componentId": "ingredient", "path": "/ingredients"}},
    {"id": "ingredient", "component": "CheckBox", "label": {"path": "name"}, "value": {"path": "done"}},
    {"id": "method-title", "component": "Text", "text": "Method", "variant": "h4"},
    {"id": "method", "component": "Steps", "items": ["Soften the onion and garlic in olive oil, 5 min.", "Add the tomatoes and stock, simmer 25 min.", "Blend smooth and season."]}
  ]}}
]
```

Example, a form:
```a2ui
[
  {"version": "v0.9", "createSurface": {"surfaceId": "booking", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
  {"version": "v0.9", "updateDataModel": {"surfaceId": "booking", "value": {"name": "", "date": "", "guests": ["2"], "notes": ""}}},
  {"version": "v0.9", "updateComponents": {"surfaceId": "booking", "components": [
    {"id": "root", "component": "Card", "child": "form"},
    {"id": "form", "component": "Column", "children": ["header", "name", "date", "guests", "notes", "actions"]},
    {"id": "header", "component": "Header", "title": "Table at Lilla Ego", "subtitle": "Västmannagatan 69 · Friday", "symbol": "fork.knife"},
    {"id": "name", "component": "TextField", "label": "Name on the booking", "value": {"path": "/name"}},
    {"id": "date", "component": "DateTimeInput", "label": "When", "value": {"path": "/date"}, "enableDate": true, "enableTime": true},
    {"id": "guests", "component": "ChoicePicker", "label": "Guests", "displayStyle": "chips", "value": {"path": "/guests"},
      "options": [{"label": "2", "value": "2"}, {"label": "4", "value": "4"}, {"label": "6", "value": "6"}]},
    {"id": "notes", "component": "TextField", "label": "Notes", "variant": "longText", "value": {"path": "/notes"}},
    {"id": "actions", "component": "Row", "justify": "end", "children": ["submit"]},
    {"id": "submit-label", "component": "Text", "text": "Request Booking"},
    {"id": "submit", "component": "Button", "child": "submit-label", "variant": "primary", "action": {"event": {"name": "book",
      "context": {"name": {"path": "/name"}, "date": {"path": "/date"}, "guests": {"path": "/guests"}, "notes": {"path": "/notes"}}}}}
  ]}}
]
```

Example, a chart (use "values" instead of "series" for a single set):
```a2ui
[
  {"version": "v0.9", "createSurface": {"surfaceId": "sthlm-week", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
  {"version": "v0.9", "updateComponents": {"surfaceId": "sthlm-week", "components": [
    {"id": "root", "component": "Card", "child": "body"},
    {"id": "body", "component": "Column", "children": ["header", "chart", "facts"]},
    {"id": "header", "component": "Header", "title": "Stockholm, last 7 days", "subtitle": "Daily high and low", "symbol": "cloud.sun.fill", "tone": "info"},
    {"id": "chart", "component": "Chart", "kind": "line", "unit": "°C", "labels": ["Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue"],
      "series": [{"name": "High", "values": [14, 12, 15, 17, 13, 11, 12]}, {"name": "Low", "values": [7, 6, 8, 9, 7, 4, 5]}]},
    {"id": "facts", "component": "KeyValue", "items": [{"key": "Warmest", "value": "Sat, 17 °C", "symbol": "thermometer.sun"}, {"key": "Rain", "value": "Thu and Mon", "symbol": "cloud.rain"}]}
  ]}}
]
```

Example, a map:
```a2ui
[
  {"version": "v0.9", "createSurface": {"surfaceId": "sofo-coffee", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
  {"version": "v0.9", "updateComponents": {"surfaceId": "sofo-coffee", "components": [
    {"id": "root", "component": "Card", "child": "body"},
    {"id": "body", "component": "Column", "children": ["header", "map", "places"]},
    {"id": "header", "component": "Header", "title": "Coffee on Södermalm", "subtitle": "3 favourites", "symbol": "cup.and.saucer.fill", "tone": "warning"},
    {"id": "map", "component": "Map", "markers": [
      {"title": "Drop Coffee", "latitude": 59.3172, "longitude": 18.0617},
      {"title": "Johan & Nyström", "latitude": 59.3135, "longitude": 18.0779},
      {"title": "Mellqvist Kaffebar", "latitude": 59.3170, "longitude": 18.0566}]},
    {"id": "places", "component": "KeyValue", "items": [{"key": "Drop Coffee", "value": "Wollmar Yxkullsgatan 10"}, {"key": "Johan & Nyström", "value": "Swedenborgsgatan 7"}, {"key": "Mellqvist Kaffebar", "value": "Hornsgatan 78"}]}
  ]}}
]
```
