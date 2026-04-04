# Apple Swift Docs Mode Handoff Contract

Use this payload shape when one Apple and Swift docs mode must hand off to the next mode.

## Inputs

- `from_mode`: `explore`, `dash-install`, or `dash-generate`
- `to_mode`: `dash-install` or `dash-generate`
- `reason`: one short explanation of why the handoff is needed

## Output

```text
status: handoff
path_type: primary
from_mode: <explore|dash-install|dash-generate>
to_mode: <dash-install|dash-generate>
query_or_request: <short-text>
next_step: <short-text>
```

## Notes

- Use this contract when `explore` finds that the requested Dash coverage is missing and the next action is Dash installation follow-up.
- Use this contract when `dash-install` cannot find a catalog match and the next action is generation guidance.
