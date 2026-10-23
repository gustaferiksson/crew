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
        let skillExamples = markdownBlocks(from: crewUISkill).filter { $0.kind == .code(language: "a2ui") }.map { String($0.content.characters) }
        return [
            turn("a1", "Show me a recipe card for pancakes with an ingredient checklist", nil, recipeReply, 40),
            turn("a2", "Can you clean up the old preview deployments?", nil, "Four previews have been idle for over two weeks. Want me to delete them?\n\n```a2ui\n\(skillExamples[0])\n```", 30),
            turn("a3", nil, #"<a2ui-action>{"context":{"choice":"delete"},"name":"decide","sourceComponentId":"delete","surfaceId":"cleanup-previews"}</a2ui-action>"#, "Deleted all four previews.", 29),
            turn("a5", "Compare the weekend flights to Bodø", nil, "Three direct options, Widerøe is the cheapest.\n\n```a2ui\n\(flightsBlock)\n```", 10),
            turn("a4", "Compare the last 7 days of weather in Stockholm as a chart", nil, weatherReply, 5),
            turn("a7", "What are the best coffee spots on Södermalm? Show them on a map.", nil, coffeeReply, 3),
            turn("a6", "Book us a table at Lilla Ego on Friday", nil, "Fill in the details and I'll send the request.\n\n```a2ui\n\(skillExamples[2])\n```", 1),
        ]
    }

    private static let flightsBlock = """
        [
          {"version": "v0.9", "createSurface": {"surfaceId": "flights-bodo", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
          {"version": "v0.9", "updateComponents": {"surfaceId": "flights-bodo", "components": [
            {"id": "root", "component": "Card", "child": "body"},
            {"id": "body", "component": "Column", "children": ["header", "badges", "table", "facts"]},
            {"id": "header", "component": "Header", "title": "Weekend flights to Bodø", "subtitle": "ARN → BOO · 1 adult", "symbol": "airplane", "tone": "info"},
            {"id": "badges", "component": "Row", "children": ["direct", "cheapest"]},
            {"id": "direct", "component": "Badge", "text": "All direct", "tone": "success", "symbol": "checkmark"},
            {"id": "cheapest", "component": "Badge", "text": "Widerøe cheapest", "tone": "info"},
            {"id": "table", "component": "Table", "columns": ["Flight", "Departs", "Duration", "Price"],
              "rows": [["SK 4112", "Fri 17:05", "1 h 35 min", "1 890 kr"], ["DY 340", "Fri 19:40", "1 h 40 min", "1 640 kr"], ["WF 811", "Sat 07:15", "1 h 50 min", "1 420 kr"]]},
            {"id": "facts", "component": "KeyValue", "items": [{"key": "Cheapest", "value": "WF 811", "symbol": "tag"}, {"key": "Fastest", "value": "SK 4112", "symbol": "hare"}]}
          ]}}
        ]
        """

    private static let recipeReply = #"""
        **Pancakes:** Whisk flour, baking powder, sugar and salt with milk, an egg and melted butter, then cook small portions in a lightly buttered pan over medium heat until golden on both sides.

        ```a2ui
        [
          {"version":"v0.9","createSurface":{"surfaceId":"pancakes-checklist","catalogId":"https://crew.gustaf.dev/catalogs/crew/v1.json"}},
          {"version":"v0.9","updateDataModel":{"surfaceId":"pancakes-checklist","value":{"ingredients":[{"name":"1 cup all-purpose flour","done":true},{"name":"2 teaspoons baking powder","done":true},{"name":"1 tablespoon sugar","done":false},{"name":"¼ teaspoon salt","done":false},{"name":"¾ cup milk, plus more if needed","done":false},{"name":"1 large egg","done":false},{"name":"2 tablespoons melted butter","done":false}]}}},
          {"version":"v0.9","updateComponents":{"surfaceId":"pancakes-checklist","components":[
            {"id":"root","component":"Card","child":"body"},
            {"id":"body","component":"Column","children":["header","badges","ingredients-title","ingredients","method-title","method"]},
            {"id":"header","component":"Header","title":"Fluffy Pancakes","subtitle":"About 8 small pancakes · 20 min","symbol":"frying.pan.fill","tone":"warning"},
            {"id":"badges","component":"Row","children":["easy","veg"]},
            {"id":"easy","component":"Badge","text":"Easy","tone":"success"},
            {"id":"veg","component":"Badge","text":"Vegetarian","tone":"neutral","symbol":"leaf"},
            {"id":"ingredients-title","component":"Text","text":"Ingredients","variant":"h4"},
            {"id":"ingredients","component":"Column","children":{"componentId":"ingredient","path":"/ingredients"}},
            {"id":"ingredient","component":"CheckBox","label":{"path":"name"},"value":{"path":"done"}},
            {"id":"method-title","component":"Text","text":"Method","variant":"h4"},
            {"id":"method","component":"Steps","items":["Mix the flour, baking powder, sugar and salt in a bowl.","Whisk the milk, egg and cooled melted butter, then fold into the dry ingredients until just combined; a few lumps are fine.","Heat a lightly buttered pan over medium heat and pour in about ¼ cup of batter per pancake.","Flip when bubbles form and the edges look set, about 2 minutes, then cook 1–2 minutes more."]}
          ]}}
        ]
        ```
        """#

    private static let weatherReply = #"""
        Stockholm’s last seven complete days (**7–13 October 2026**) were warmest on 8 October at **14°C**, while 9 October was wettest with **32.2 mm** of precipitation. Source: [Open-Meteo historical weather](https://archive-api.open-meteo.com/v1/archive?latitude=59.3293&longitude=18.0686&start_date=2026-10-07&end_date=2026-10-13&daily=temperature_2m_max,temperature_2m_min,precipitation_sum&timezone=Europe%2FStockholm).

        ```a2ui
        [
          {"version":"v0.9","createSurface":{"surfaceId":"stockholm-weather-oct7-13","catalogId":"https://crew.gustaf.dev/catalogs/crew/v1.json"}},
          {"version":"v0.9","updateComponents":{"surfaceId":"stockholm-weather-oct7-13","components":[
            {"id":"root","component":"Card","child":"body"},
            {"id":"body","component":"Column","children":["header","temperature","rain-title","rain","source"]},
            {"id":"header","component":"Header","title":"Stockholm weather","subtitle":"7–13 October 2026 · Stockholm local time","symbol":"cloud.sun.fill","tone":"info"},
            {"id":"temperature","component":"Chart","kind":"line","unit":"°C","labels":["7 Oct","8 Oct","9 Oct","10 Oct","11 Oct","12 Oct","13 Oct"],"series":[{"name":"Daily high","values":[13.2,14.0,11.9,7.3,8.4,8.7,9.0]},{"name":"Daily low","values":[7.6,8.3,6.5,4.0,6.9,5.8,4.8]}]},
            {"id":"rain-title","component":"Text","text":"Daily precipitation","variant":"h4"},
            {"id":"rain","component":"Chart","kind":"bar","unit":"mm","labels":["7 Oct","8 Oct","9 Oct","10 Oct","11 Oct","12 Oct","13 Oct"],"values":[0,5.9,32.2,5.4,10.7,9.5,0]},
            {"id":"source","component":"Text","text":"Source: Open-Meteo historical gridded weather data for Stockholm; not a single weather station.","variant":"caption"}
          ]}}
        ]
        ```
        """#

    private static let coffeeReply = #"""
        My shortlist: **Drop Coffee** for single-origin filter coffee, **Johan & Nyström** for specialty coffee near Mariatorget, and **Pascal** for coffee with excellent pastries. Sources: [Stockholm coffee guide](https://www.stockholm-spirit.com/guides/stockholm-coffee-third-wave/), [Pascal recommendations](https://worldofmouth.app/restaurants/cafe--bageri-pascal); map locations verified with OpenStreetMap.

        ```a2ui
        [
          {"version":"v0.9","createSurface":{"surfaceId":"sodermalm-coffee-picks","catalogId":"https://crew.gustaf.dev/catalogs/crew/v1.json"}},
          {"version":"v0.9","updateComponents":{"surfaceId":"sodermalm-coffee-picks","components":[
            {"id":"root","component":"Card","child":"body"},
            {"id":"body","component":"Column","children":["header","map","places","note"]},
            {"id":"header","component":"Header","title":"Coffee on Södermalm","subtitle":"Three specialty-coffee picks","symbol":"cup.and.saucer.fill","tone":"info"},
            {"id":"map","component":"Map","markers":[
              {"title":"Drop Coffee","latitude":59.3169067,"longitude":18.0628136},
              {"title":"Johan & Nyström","latitude":59.3164328,"longitude":18.0638898},
              {"title":"Pascal Café & Bakery","latitude":59.3120889,"longitude":18.0789422}
            ]},
            {"id":"places","component":"KeyValue","items":[
              {"key":"Drop Coffee","value":"Wollmar Yxkullsgatan 10 · My first pick for single-origin filter coffee."},
              {"key":"Johan & Nyström","value":"Swedenborgsgatan 7 · Specialty roaster and coffee bar, around the corner from Drop."},
              {"key":"Pascal Café & Bakery","value":"Skånegatan 76 · Go for specialty coffee with a cinnamon bun or croissant."}
            ]},
            {"id":"note","component":"Text","text":"Check opening hours before heading out. Pins use OpenStreetMap; Johan & Nyström is pinned to its street address.","variant":"caption"}
          ]}}
        ]
        ```
        """#

    static func productTurns(_ now: Date, count: Int) -> [Turn] {
        (0..<count).map { index in
            let start = now.addingTimeInterval(Double(index - count) * 600)
            return Turn(
                id: "p\(index)", prompt: Prompt(text: "Find a warm wool blanket under 900 kr", sentAt: start),
                reply: productReply.replacingOccurrences(of: "SURFACE", with: "blankets-\(index)"),
                status: .complete, startedAt: start, finishedAt: start.addingTimeInterval(40)
            )
        }
    }

    private static let productReply = #"""
        Three blankets fit the budget. Prices include shipping, and all three are in stock today.

        **My pick:** the **Fjäll** if warmth matters most, the **Skog** if you want something lighter for summer evenings.

        ```a2ui
        [
          {"version":"v0.9","createSurface":{"surfaceId":"SURFACE","catalogId":"https://crew.gustaf.dev/catalogs/crew/v1.json"}},
          {"version":"v0.9","updateComponents":{"surfaceId":"SURFACE","components":[
            {"id":"root","component":"Card","child":"body"},
            {"id":"body","component":"Column","children":["header","one-image","one","divider1","two-image","two","divider2","three-image","three","note"]},
            {"id":"header","component":"Header","title":"Wool blankets under 900 kr","subtitle":"Natural colours · 130 × 180 cm · shipping included","symbol":"gift","tone":"info"},
            {"id":"one-image","component":"Image","url":"https://picsum.photos/id/1062/1788/1788","description":"Fjäll blanket folded on a chair"},
            {"id":"one","component":"Text","text":"### 1. [Fjäll, Example Weavers](https://example.com/fjall) · 795 kr\n**In stock in grey and oat.** Heavy lambswool woven on an old shuttle loom, so the edges are a little uneven by design. It is the warmest of the three by a wide margin.\n\n**The trade-off:** it is dry-clean only and sheds for the first few weeks. Free returns within 30 days."},
            {"id":"divider1","component":"Divider"},
            {"id":"two-image","component":"Image","url":"https://picsum.photos/id/1025/1600/2000","description":"Skog blanket on a sofa"},
            {"id":"two","component":"Text","text":"### 2. [Skog, Example Mill](https://example.com/skog) · 640 kr\n**In stock in moss and sand.** A lighter merino weave that works on a bed in summer and on the sofa in winter. Machine washable on the wool programme.\n\nThinner than it looks in the photos, so it is not the one for a cold cabin."},
            {"id":"divider2","component":"Divider"},
            {"id":"three-image","component":"Image","url":"https://picsum.photos/id/1084/1600/2000","description":"Hav blanket with fringes"},
            {"id":"three","component":"Text","text":"### 3. [Hav, Example Studio](https://example.com/hav) · 880 kr\n**Only the blue is in stock.** Recycled wool with long fringes and a soft brushed finish. The softest of the three against the skin.\n\nReviews mention pilling after a year of daily use."},
            {"id":"note","component":"Text","variant":"caption","text":"Prices checked today. Nothing is ordered."}
          ]}}
        ]
        ```
        """#
}
