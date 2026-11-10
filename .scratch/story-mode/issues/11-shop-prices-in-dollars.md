# Shop prices in dollars: the tech tree shows and charges money costs

Type: task (AFK)
Status: open
Blocked by: 10

## Question

Make Story Mode upgrades cost `money=<amount>` (through a mod `upgrades.yaml` override), and make the tech tree display and charge dollar costs. `GameWorld.canAfford` already reads `inventory.<key>`; the display in `content/techtree/` likely needs work.

## Done when

- Five vanilla upgrades repriced in dollars as a test.
- Harness: a screenshot of the tech tree shows dollar prices; buying one deducts the right amount; an unaffordable one is refused.
