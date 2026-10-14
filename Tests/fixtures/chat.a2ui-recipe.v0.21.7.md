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