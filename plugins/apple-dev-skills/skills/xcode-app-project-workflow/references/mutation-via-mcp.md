# Mutation via MCP

Preferred mutation order:

1. Use Xcode MCP mutation tools.
2. Verify each mutation with read/search tools.
3. If MCP mutation path fails and direct filesystem fallback is considered, route to `$xcode-app-project-workflow` for the full mutation safety gate.

Never jump directly to raw file edits in Xcode-managed scope without safety gate completion.
