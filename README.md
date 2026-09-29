# PointFreeMCP

A [Point-Free](https://www.pointfree.co) MCP server for Claude Code and other MCP clients, modelled after [sosumi](https://sosumi.ai). It lets an assistant search Point-Free episodes, read transcripts, browse collections and read blog posts, returning clean markdown.

## Requirements

- macOS 26 and Xcode 26 (Swift toolchain, WebKit for the sign-in window)
- A Point-Free membership for members-only transcripts (free episodes and blog posts work without one)

## Install

```bash
swift build -c release
claude mcp add pointfree -- "$PWD/.build/release/pointfree-mcp" serve
```

For other MCP clients, add a stdio server entry:

```json
{
  "mcpServers": {
    "pointfree": {
      "command": "/absolute/path/to/.build/release/pointfree-mcp",
      "args": ["serve"]
    }
  }
}
```

Members-only episodes need a signed-in session first: run `pointfree-mcp login` once, or call the `login` tool from your MCP client.

## Commands

- `pointfree-mcp serve` (default) runs the stdio MCP server.
- `pointfree-mcp login` opens a window with GitHub sign-in and saves the Point-Free session. The window polls the WebKit cookie store every 2 seconds and validates each candidate `pf_session` cookie against `https://www.pointfree.co/account` before saving it (the site also sets an anonymous `pf_session` during the OAuth redirect, which is rejected). The session lives 7 days; after that call the `login` tool again.
  - `--cookie <value>` is a fallback: pass the value of the `pf_session` cookie copied from your browser's dev tools.
  - `--timeout <seconds>` limits how long the window waits (default 300).
  - Exit codes: 0 saved, 1 cancelled or Quit, 2 cookie rejected, 3 timed out, 4 other error.
  - The `login` tool also accepts a `force` argument to sign in again even when a saved session exists.
- `pointfree-mcp status` shows whether a valid session is saved.
- `pointfree-mcp logout` removes the saved session.

## Tools

| Tool | Example prompt |
| --- | --- |
| `searchPointFree` | "Search Point-Free for how to test effects in TCA." |
| `fetchEpisode` | "Fetch Point-Free episode 381, the section about testing." |
| `listEpisodes` | "List the latest Point-Free episodes." |
| `fetchCollection` | "Show the Composable Architecture collection and its testing section." |
| `listBlogPosts` | "List Point-Free blog posts about LazyState." |
| `fetchBlogPost` | "Read the Point-Free blog post about LazyState 1.0." |
| `login` | "Sign in to Point-Free." (opens the sign-in window) |

## Notes

- Site search shows at most about 50 cards; narrow it with scope and access filters.
- The blog Atom feed provides only the post list and metadata (number, title, date, link, blurb). `fetchBlogPost` fetches the post body on demand from the post page, `https://www.pointfree.co/blog/posts/{slug}`.
- Responses are cached in memory for 1 hour. Transcripts are never written to disk.
- The session file is `~/.pointfree-mcp/session.json` (mode 0600). Set `POINTFREE_MCP_HOME` to use another directory.
- Live tests hit the real site and are skipped by default:

  ```bash
  POINTFREE_LIVE=1 swift test --filter LiveTests
  ```

## License and content

The code is MIT licensed (see `LICENSE`). Point-Free videos and transcripts belong to Point-Free; this server fetches them on demand using your own membership session and does not store them. Blog posts are licensed CC BY-NC-SA 4.0. This tool is not meant for redistributing content.

## Linting

The repository ships no lint configuration. Generic server-side lint rules (Foundation avoidance, SQL-injection heuristics on markdown string interpolation, cyclomatic complexity of parsers) do not apply to this project.
