# PointFreeMCP

A [Point-Free](https://www.pointfree.co) MCP server for Claude Code and any other MCP client, modelled after [sosumi](https://sosumi.ai) for Apple documentation. It lets your coding assistant search the Point-Free video catalog, read episode transcripts with all their code, browse collections and read the Point-Free Pointers blog, and returns everything as clean markdown. Members-only transcripts are fetched with your own Point-Free membership after a one-time GitHub sign-in.

Nothing is downloaded ahead of time: every tool call goes to pointfree.co on demand, responses are cached in memory for an hour, and transcripts are never written to disk.

## Contents

- [What you get](#what-you-get)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Signing in](#signing-in)
- [Tools](#tools)
- [Usage tips](#usage-tips)
- [CLI commands](#cli-commands)
- [Configuration](#configuration)
- [Project layout](#project-layout)
- [Development](#development)
- [Troubleshooting](#troubleshooting)
- [Privacy and security](#privacy-and-security)
- [License and content](#license-and-content)

## What you get

| Tool | What it does | Login needed |
| --- | --- | --- |
| `searchPointFree` | Full-text search over transcripts, code and titles of all episodes, with timestamped chapter links | No |
| `fetchEpisode` | Episode metadata, references, link to the code samples, and the full transcript with code blocks; can fetch a single chapter | Only for members-only episodes |
| `listEpisodes` | All episodes, newest first, with dates, durations and access level | No |
| `fetchCollection` | Curated collections, their sections and the episodes inside | No |
| `listBlogPosts` | Point-Free Pointers posts (library releases, migration guides, monthly recaps) | No |
| `fetchBlogPost` | Full text of a blog post with code blocks | No |
| `login` | Opens the GitHub sign-in window from inside your MCP client | — |

Typical prompts once the server is connected:

- "Search Point-Free for how to test effects in TCA."
- "Fetch Point-Free episode 381, the chapter at 5:49."
- "Show the Composable Architecture collection and open its Testing section."
- "What changed in LazyState 1.0? Read the Point-Free blog post."

## How it works

```
Claude Code ──stdio JSON-RPC──▶ pointfree-mcp serve
                                   │
                                   ├─ /api/episodes, /search, /collections, /blog/feed/atom.xml   (public)
                                   ├─ /episodes/{id}, /blog/posts/{slug}                          (HTML, parsed)
                                   └─ Cookie: pf_session=…  only for www.pointfree.co, only if saved
                                   
pointfree-mcp login ──▶ WKWebView window ──▶ GitHub OAuth ──▶ validated pf_session ──▶ ~/.pointfree-mcp/session.json
```

- Episode lists and metadata come from the site's public JSON API.
- Search and collections are parsed from the public HTML pages.
- Transcripts are parsed from the episode page (`article` element): chapters, speakers, timestamps, paragraphs, lists, quotes and `pre > code` blocks. For a members-only episode the anonymous page contains only a preview; the server compares the table of contents with the article to detect that and asks you to sign in.
- Blog metadata comes from the Atom feed; the post body is fetched from the post page.
- The Point-Free session cookie lives 7 days. When it expires the tools say so and the `login` tool renews it.

## Requirements

- macOS 26 and Xcode 26 (Swift 6 toolchain; AppKit and WebKit are used for the sign-in window).
- A Point-Free membership for members-only transcripts. Free episodes, search, collections and the blog work without one.
- Claude Code, or any MCP client that can launch a stdio server.

## Installation

Build a release binary:

```bash
git clone git@github.com:EvgeniiSamarin/PointFreeMCP.git
cd PointFreeMCP
swift build -c release
```

Register it with Claude Code (user scope makes it available in every project):

```bash
claude mcp add --scope user pointfree -- "$PWD/.build/release/pointfree-mcp" serve
```

Check the connection:

```bash
claude mcp list
```

You should see `pointfree: … ✔ Connected`. Start a new Claude Code session and the seven tools are available.

For other MCP clients add a stdio server entry to their configuration:

```json
{
  "mcpServers": {
    "pointfree": {
      "command": "/absolute/path/to/PointFreeMCP/.build/release/pointfree-mcp",
      "args": ["serve"]
    }
  }
}
```

## Signing in

Members-only episodes need a signed-in Point-Free session. Either call the `login` tool from your MCP client ("Sign in to Point-Free") or run it from the terminal:

```bash
.build/release/pointfree-mcp login
```

What happens:

1. A window titled "Sign in to Point-Free" opens on `https://www.pointfree.co/login`. Click "Login with GitHub" and complete the GitHub flow (password + 2FA works; passkeys and hardware security keys may not work inside the embedded window).
2. The window polls the WebKit cookie store every 2 seconds. Every candidate `pf_session` cookie is validated against `https://www.pointfree.co/account` before it is accepted: the site also sets an anonymous `pf_session` during the OAuth redirect, and that one is rejected.
3. As soon as a valid cookie is found the window closes itself and the session is saved to `~/.pointfree-mcp/session.json` (mode 0600).
4. The WebKit profile persists in `~/Library/WebKit/pointfree-mcp`, so when the session expires after 7 days the next `login` usually completes without any clicks.

Options and exit codes:

- `--cookie <value>` saves a `pf_session` value copied from your browser's developer tools instead of opening a window.
- `--timeout <seconds>` limits how long the window waits (default 300; the `login` tool uses 290).
- Exit codes: `0` saved, `1` cancelled (window closed or ⌘Q), `2` cookie rejected by the site, `3` timed out, `4` other error (network, file write).
- While the window is open the process shows a Dock icon and a minimal menu (⌘Q cancels; standard Edit shortcuts work in form fields).
- The `login` tool accepts `force: true` to sign in again even when a saved session exists.

Check or clear the session:

```bash
.build/release/pointfree-mcp status
.build/release/pointfree-mcp logout
```

To reset everything, including the remembered GitHub sign-in, also delete `~/Library/WebKit/pointfree-mcp`.

## Tools

All tools return one markdown text block. Errors are returned as tool errors with a plain explanation (for example "This episode is for Point-Free members. Call the `login` tool…").

### `searchPointFree`

| Argument | Type | Description |
| --- | --- | --- |
| `query` | string, required | Search terms, e.g. `Sendable`, `@Shared`, `navigation stack` |
| `scope` | `dialogue` \| `code` \| `titles` | Match only spoken dialogue, code samples or titles |
| `access` | `free` \| `subscriber-only` | Only free or only members-only episodes |
| `sort` | `newest` \| `oldest` | Default is relevance |

Returns matching episodes with a snippet and chapter hits as links like `https://www.pointfree.co/episodes/ep381-…#t349`. The site returns at most about 50 cards; the header says "Showing 49 of 165" when more exist, so narrow with `scope` or `access`.

### `fetchEpisode`

| Argument | Type | Description |
| --- | --- | --- |
| `episode` | string, required | Number (`381`), slug (`ep381-designing-for-isolation-naively`) or URL; a `#t349` fragment selects a chapter |
| `section` | string | One chapter: a timestamp (`t349`, `5:49`) or a chapter slug (`introduction`) |

Returns a header (title, date, duration, access, URL, link to the episode's folder in [episode-code-samples](https://github.com/pointfreeco/episode-code-samples)), the references list, and the transcript: `## Chapter [m:ss](url#tNNN)`, speaker names in bold, paragraphs, lists, quotes and ```` ```swift ```` blocks. With `section` only that chapter is returned; an unknown section lists the available ones.

### `listEpisodes`

| Argument | Type | Description |
| --- | --- | --- |
| `filter` | string | Case-insensitive substring of the title |
| `limit` | integer | Default 50 |

### `fetchCollection`

| Argument | Type | Description |
| --- | --- | --- |
| `slug` | string | Collection slug, e.g. `composable-architecture`; omit to list all collections |
| `section` | string | Section slug inside the collection, e.g. `testing`; lists that section's episodes |

### `listBlogPosts`

| Argument | Type | Description |
| --- | --- | --- |
| `filter` | string | Case-insensitive substring of the post title |
| `limit` | integer | Default 30 |

### `fetchBlogPost`

| Argument | Type | Description |
| --- | --- | --- |
| `post` | string, required | Post number (`228`), slug (`228-lazystate-1-0-now-available-to-everyone`) or URL |

### `login`

| Argument | Type | Description |
| --- | --- | --- |
| `force` | boolean | Sign in again even if a valid session exists |

Reports the saved session if it is still valid; otherwise launches the sign-in window (as a child process of the server) and waits for it.

## Usage tips

- Start with `searchPointFree`, then fetch only the chapter you need with `section` to keep the context small. Search hits already carry the `#tNNN` timestamps you can pass as `section`.
- Use `scope: code` when you are looking for an API or a snippet, `scope: dialogue` for explanations.
- The episode header links to the code samples folder on GitHub; the assistant can open it with its usual web tools.
- For a learning path use `fetchCollection` without arguments, then with `slug`, then with `slug` and `section`.
- The blog is the fastest way to learn what changed in a library release; `listBlogPosts` with `filter` narrows it down.

## CLI commands

| Command | Description |
| --- | --- |
| `pointfree-mcp serve` | Run the stdio MCP server (default when no subcommand is given). Only JSON-RPC goes to stdout; logs go to stderr. |
| `pointfree-mcp login [--cookie <value>] [--timeout <s>]` | Sign in (see above) |
| `pointfree-mcp status` | Show whether a valid session is saved |
| `pointfree-mcp logout` | Delete the saved session |
| `pointfree-mcp --version` | Print the version |

## Configuration

| Setting | Default | Description |
| --- | --- | --- |
| `POINTFREE_MCP_HOME` | `~/.pointfree-mcp` | Directory of `session.json` |
| `POINTFREE_LIVE=1` | unset | Enables the live tests that hit the real site |
| Cache | 1 hour, 50 entries, in memory | Episode list, pages, search results and the blog feed |
| User-Agent | `pointfree-mcp/0.1.0` | Sent with every request |

The HTTP client never follows redirects and never stores cookies; the session cookie is added only to requests for `www.pointfree.co`.

## Project layout

```
Package.swift                  Swift 6.2 tools, macOS 26
Sources/
  PointFreeKit/                library: everything except AppKit and the MCP transport
    Models/                    Episode, EpisodeRef/SectionRef, Transcript, SearchResult, Collection, BlogPost
    Client/                    HTTPClient (URLSession, no redirects), PointFreeClient (site API), SearchQuery, PointFreeError
    Parsing/                   EpisodePageParser, SearchPageParser, CollectionsParser, BlogFeedParser, BlogContentParser, InlineMarkdown
    Rendering/                 MarkdownRenderer
    Session/                   Session, SessionStore (0600 file)
    Cache/                     MemoryCache (TTL + bounded size)
    Tools/                     ToolDefinitions (JSON schemas), ToolCatalog (handlers), ToolArguments, LoginLauncher
  PointFreeMCP/                executable `pointfree-mcp`
    EntryPoint.swift           synchronous main: runs the login window before any async code
    PointFreeMCPCommand.swift  root command (swift-argument-parser)
    Commands/                  Serve, Login, Status, Logout
    Server/                    MCPServerFactory: tool list + call handler on the MCP Swift SDK
    LoginWindow/               LoginWindowController: WKWebView, cookie polling, validation, menu, Quit handling
Tests/PointFreeKitTests/       Swift Testing; synthetic HTML/JSON fixtures in Fixtures/; live tests behind POINTFREE_LIVE
docs/superpowers/              design spec and implementation plan
```

Dependencies: [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk), [SwiftSoup](https://github.com/scinfu/SwiftSoup), [swift-argument-parser](https://github.com/apple/swift-argument-parser), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), [swift-log](https://github.com/apple/swift-log).

All external effects (HTTP, session file, login process, clock) are injected through swift-dependencies, so the tool handlers are unit-tested against stubs and never touch the network.

## Development

```bash
swift build                                   # debug build
swift test                                    # unit tests (live tests are skipped)
POINTFREE_LIVE=1 swift test --filter LiveTests  # live tests against pointfree.co
```

Smoke-test the server by hand (the `sleep` keeps stdin open while the handler fetches from the network):

```bash
(printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetchEpisode","arguments":{"episode":"1","section":"introduction"}}}'; sleep 10) \
  | .build/debug/pointfree-mcp serve
```

Adding a tool: describe it in `ToolDefinitions.swift` (name, description, JSON schema), implement the handler in `ToolCatalog.swift`, add a renderer in `MarkdownRenderer.swift` if it needs a new output shape, and cover it in `ToolCatalogTests.swift` with stubbed dependencies.

Parsers are written against synthetic fixtures that mirror the live markup (`Tests/PointFreeKitTests/Fixtures/`). Real pages for debugging go into `Tests/live/`, which is git-ignored: Point-Free transcripts are copyrighted and must not be committed.

The repository ships no lint configuration. Generic server-side lint rules (Foundation avoidance, SQL-injection heuristics on markdown string interpolation, cyclomatic complexity of parsers) do not apply to this project.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| "This episode is for Point-Free members. Call the `login` tool" | Sign in (tool or CLI). Free episodes never need it. |
| "Your Point-Free session expired" | The 7-day cookie ended; run `login` again. The saved session file is removed automatically. |
| "Signed in, but the transcript is truncated…" | The account has no active membership, or the page changed. Try `login` with `force: true`; check the membership on pointfree.co. |
| The sign-in window is blank or behind other windows | Look for the Dock icon and click it. If the page never loads, check the network; the window logs navigation events to stderr. |
| Login exits with code 2 | The cookie was rejected by `/account`. Sign in again; with `--cookie`, copy the full `pf_session` value. |
| Passkey or security key does not work in the window | Use password + 2FA, or `--cookie`. |
| "pointfree.co markup changed (…)" | The site's HTML no longer matches a parser. Open an issue with the URL. |
| Search shows "Showing N of M" | The site caps results at about 50; narrow with `scope` or `access`. |
| `claude mcp list` shows the server as failed | Rebuild with `swift build -c release`; the registered path must point to the release binary. |

## Privacy and security

- The only thing stored on disk is the Point-Free session cookie in `~/.pointfree-mcp/session.json` (0600) and WebKit's own profile for the sign-in window.
- The cookie is sent only to `www.pointfree.co`. Public endpoints are requested without it.
- Logs never contain cookie values or full URLs with query strings; navigation logs show host and path only.
- The server never types credentials: you sign in yourself in the window.

## License and content

The code is MIT licensed (see `LICENSE`).

Point-Free videos and transcripts belong to Point-Free, Inc. This server fetches them on demand using your own membership session, keeps them only in memory, and is not meant for redistributing content. Blog posts are licensed CC BY-NC-SA 4.0. Please support Point-Free with a [membership](https://www.pointfree.co/pricing).

Thanks to [Point-Free](https://www.pointfree.co) for the open-source [site](https://github.com/pointfreeco/pointfreeco) and libraries, and to [sosumi](https://sosumi.ai) for the idea.
