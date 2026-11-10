# Issue tracker: GitHub

Issues for this project live on GitHub at https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod. Use the `gh` CLI for all operations; run it from the `Dome Keeper` folder (the clone) so it infers the repo, or pass `-R cejdan/Dome-Keeper-Story-Mode-Mod`.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body-file <file>` (write multi-line bodies to a file in the scratchpad first).
- **Read an issue**: `gh issue view <n> --json number,title,body,labels,assignees,comments,state`.
- **List issues**: `gh issue list --state open --label <label> --json number,title,labels,assignees`.
- **Sub-issue of a parent**: `gh issue edit <parent> --add-sub-issue <child>` (`gh` 2.94+), or `gh api --method POST repos/cejdan/Dome-Keeper-Story-Mode-Mod/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>` where the db id is `gh api repos/cejdan/Dome-Keeper-Story-Mode-Mod/issues/<n> --jq .id`.
- **Blocking**: GitHub's native issue dependencies. `gh issue edit <child> --add-blocked-by <blocker>` (`gh` 2.94+), or `gh api --method POST repos/cejdan/Dome-Keeper-Story-Mode-Mod/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`. A ticket is unblocked when every blocker is closed.
- **Count open blockers**: `gh api repos/cejdan/Dome-Keeper-Story-Mode-Mod/issues/<n> --jq .issue_dependencies_summary.blocked_by` (0 means startable).
- **Comment**: `gh issue comment <n> --body-file <file>`.
- **Labels**: `gh issue edit <n> --add-label "..."` / `--remove-label "..."`.
- **Close**: comment first, then `gh issue close <n>` (`gh issue close --comment` on an already-closed issue silently drops the comment).

File issues only into `cejdan/Dome-Keeper-Story-Mode-Mod`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is one issue; its **tickets** are sub-issues of it.

- **Map**: the issue labelled `wayfinder:map` ("Story Mode mod"). Find it with `gh issue list --label wayfinder:map --state all`. Its body holds Destination / Notes / Decisions so far / Not yet specified / Out of scope.
- **Ticket**: a sub-issue of the map, labelled `wayfinder:<type>` (`research`, `prototype`, `grilling`, `task`). The body's first line says `Mode: HITL` or `Mode: AFK`; then `## Question`, and for build tasks `## Done when`.
- **Frontier**: the map's open sub-issues with no open blocker and no assignee; lowest issue number first. `gh api repos/cejdan/Dome-Keeper-Story-Mode-Mod/issues/<map>/sub_issues --paginate --jq '.[] | select(.state=="open" and (.assignees|length)==0 and .issue_dependencies_summary.blocked_by==0) | "\(.number) \(.title)"'`
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: post the answer as a comment headed `## Answer`, close the issue, then add a line (linked name + gist) to the map's Decisions so far.
- **Research findings**: committed on a throwaway `research/<slug>` branch and pushed, never merged; the ticket's answer links to it.
- **Out of scope**: close the ticket as "not planned" and add a line to the map's Out of scope.
