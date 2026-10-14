import Foundation

extension ChatFixture {
    static func a2uiTurns(_ now: Date) -> [Turn] {
        let turn = { (id: String, prompt: String?, hidden: String?, reply: String, minutesAgo: Double) in
            let start = now.addingTimeInterval(-minutesAgo * 60)
            return Turn(
                id: id, prompt: prompt.map { Prompt(text: $0, sentAt: start) }, hiddenText: hidden, reply: reply,
                status: .complete, startedAt: start, finishedAt: start.addingTimeInterval(6)
            )
        }
        return [
            turn("a1", "Show me a recipe card for pancakes with an ingredient checklist", nil, realRecipeReply, 40),
            turn("a2", "Can you clean up the old preview deployments?", nil, "Four previews have been idle for over two weeks. Want me to delete them?\n\n```a2ui\n\(richUIApprovalExample)\n```", 30),
            turn("a3", nil, #"<a2ui-action>{"context":{"choice":"delete"},"name":"decide","sourceComponentId":"delete","surfaceId":"cleanup-previews"}</a2ui-action>"#, "Deleted all four previews.", 29),
            turn("a5", "Compare the weekend flights to Bodø", nil, "Three direct options, Widerøe is the cheapest.\n\n```a2ui\n\(flightsBlock)\n```", 10),
            turn("a4", "Plot my steps for the week", nil, "Here's the week at a glance.\n\n```a2ui\n\(chartBlock)\n```", 5),
            turn("a6", "Book us a table at Lilla Ego on Friday", nil, "Fill in the details and I'll send the request.\n\n```a2ui\n\(richUIFormExample)\n```", 1),
        ]
    }

    private static let flightsBlock = """
        [
          {"version": "v0.9", "createSurface": {"surfaceId": "flights-bodo", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
          {"version": "v0.9", "updateComponents": {"surfaceId": "flights-bodo", "components": [
            {"id": "root", "component": "Card", "child": "body"},
            {"id": "body", "component": "Column", "children": ["title", "table", "divider", "facts"]},
            {"id": "title", "component": "Text", "text": "Weekend flights to Bodø", "variant": "h4"},
            {"id": "table", "component": "Table", "columns": ["Flight", "Departs", "Price"],
              "rows": [["SK 4112", "Fri 17:05", "1 890 kr"], ["DY 340", "Fri 19:40", "1 640 kr"], ["WF 811", "Sat 07:15", "1 420 kr"]]},
            {"id": "divider", "component": "Divider"},
            {"id": "facts", "component": "KeyValue", "items": [{"key": "Cheapest", "value": "WF 811"}, {"key": "Fastest", "value": "SK 4112, 1 h 35 min"}]}
          ]}}
        ]
        """

    private static let chartBlock = """
        [
          {"version": "v0.9", "createSurface": {"surfaceId": "steps", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
          {"version": "v0.9", "updateComponents": {"surfaceId": "steps", "components": [
            {"id": "root", "component": "Chart", "kind": "bar", "values": [8200, 10400, 6100, 12000, 9300]}
          ]}}
        ]
        """

    private static let realRecipeReply = #"""
        **Pancakes:** Whisk flour, baking powder, sugar and salt with milk, an egg and melted butter, then cook small portions in a lightly buttered pan over medium heat until golden on both sides.

        ```a2ui
        [
          {"version":"v0.9","createSurface":{"surfaceId":"pancakes-checklist","catalogId":"https://crew.gustaf.dev/catalogs/crew/v1.json"}},
          {"version":"v0.9","updateDataModel":{"surfaceId":"pancakes-checklist","value":{"ingredients":[{"name":"1 cup all-purpose flour","done":false},{"name":"2 teaspoons baking powder","done":false},{"name":"1 tablespoon sugar","done":false},{"name":"¼ teaspoon salt","done":false},{"name":"¾ cup milk, plus more if needed","done":false},{"name":"1 large egg","done":false},{"name":"2 tablespoons melted butter, plus extra for the pan","done":false}]}}},
          {"version":"v0.9","updateComponents":{"surfaceId":"pancakes-checklist","components":[
            {"id":"root","component":"Card","child":"body"},
            {"id":"body","component":"Column","children":["title","meta","ingredients-title","ingredients","divider","method-title","step1","step2","step3","step4","serve"]},
            {"id":"title","component":"Text","text":"Fluffy Pancakes","variant":"h3"},
            {"id":"meta","component":"Text","text":"About 8 small pancakes · 20 minutes","variant":"caption"},
            {"id":"ingredients-title","component":"Text","text":"Ingredient checklist","variant":"h4"},
            {"id":"ingredients","component":"Column","children":{"componentId":"ingredient","path":"/ingredients"}},
            {"id":"ingredient","component":"CheckBox","label":{"path":"name"},"value":{"path":"done"}},
            {"id":"divider","component":"Divider"},
            {"id":"method-title","component":"Text","text":"Method","variant":"h4"},
            {"id":"step1","component":"Text","text":"1. Mix the flour, baking powder, sugar and salt in a bowl."},
            {"id":"step2","component":"Text","text":"2. Whisk the milk, egg and cooled melted butter separately. Fold into the dry ingredients just until combined; a few lumps are fine. Add a splash of milk if too thick to pour."},
            {"id":"step3","component":"Text","text":"3. Heat a lightly buttered nonstick pan over medium heat. Pour in roughly ¼ cup of batter per pancake."},
            {"id":"step4","component":"Text","text":"4. Cook until bubbles form and the edges look set, about 2 minutes. Flip and cook for another 1–2 minutes, until golden and cooked through."},
            {"id":"serve","component":"Text","text":"Serve warm with maple syrup, berries or yogurt.","variant":"body"}
          ]}}
        ]
        ```
        """#
}
