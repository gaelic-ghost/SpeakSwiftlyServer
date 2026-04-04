# Allowlist Guidance

If official commands are blocked by sandbox or allowlist policy, advise user to allow safe prefixes in `~/.codex/rules`.

## Typical safe prefixes

- `["xcodebuild"]`
- `["xcrun"]`
- `["swift"]`
- `["swiftly"]`
- `["xcode-select"]`

## Message template

"The fallback command is blocked by local rules. If you want seamless Apple tooling fallback, add the command prefix to `~/.codex/rules` and rerun. I can guide the exact rule you need."

Do not suggest broad or unsafe allowlist patterns.
