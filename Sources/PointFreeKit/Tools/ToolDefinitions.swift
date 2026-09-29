public struct ToolDefinition: Equatable, Sendable {
  public var name: String
  public var description: String
  public var inputSchemaJSON: String
}

public enum ToolDefinitions {
  public static let all: [ToolDefinition] = [
    ToolDefinition(
      name: "searchPointFree",
      description: "Search the Point-Free (pointfree.co) video catalog: transcripts, code and titles of all episodes about Swift, SwiftUI, TCA, dependencies, navigation, SQLite, concurrency. Returns matching episodes with snippets and timestamped chapter links. No login needed.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "query":{"type":"string","description":"Search terms, e.g. \\"Sendable\\", \\"@Shared\\", \\"navigation stack\\""},
        "scope":{"type":"string","enum":["dialogue","code","titles"],"description":"Limit matching to spoken dialogue, code samples, or episode titles"},
        "access":{"type":"string","enum":["free","subscriber-only"],"description":"Only free or only members-only episodes"},
        "sort":{"type":"string","enum":["newest","oldest"],"description":"Sort order; default is relevance"}
      },"required":["query"]}
      """
    ),
    ToolDefinition(
      name: "fetchEpisode",
      description: "Fetch a Point-Free episode as markdown: metadata, references, link to code samples, and the full transcript with code blocks and timestamped chapters. Accepts an episode number (381), slug (ep381-designing-for-isolation-naively) or URL. Members-only episodes require the `login` tool first. Use `section` to fetch one chapter and save context.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "episode":{"type":"string","description":"Episode number, slug, or pointfree.co URL (a #tNNN fragment selects a section)"},
        "section":{"type":"string","description":"Optional chapter: timestamp like \\"t349\\" or \\"5:49\\", or chapter slug like \\"introduction\\""}
      },"required":["episode"]}
      """
    ),
    ToolDefinition(
      name: "listEpisodes",
      description: "List Point-Free episodes, newest first: number, title, date, duration and access (Free / Members only). Optional title filter.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "filter":{"type":"string","description":"Case-insensitive substring to match in the title"},
        "limit":{"type":"integer","description":"Maximum number of episodes to return (default 50)"}
      }}
      """
    ),
    ToolDefinition(
      name: "fetchCollection",
      description: "Browse Point-Free collections (curated learning paths). Without arguments lists all collections; with `slug` lists the collection's sections; with `slug` and `section` lists the episodes of that section.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "slug":{"type":"string","description":"Collection slug, e.g. composable-architecture"},
        "section":{"type":"string","description":"Section slug within the collection, e.g. testing"}
      }}
      """
    ),
    ToolDefinition(
      name: "listBlogPosts",
      description: "List posts from the Point-Free Pointers blog (library release announcements, migration guides, monthly recaps), newest first. Optional title filter. No login needed.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "filter":{"type":"string","description":"Case-insensitive substring to match in the post title"},
        "limit":{"type":"integer","description":"Maximum number of posts to return (default 30)"}
      }}
      """
    ),
    ToolDefinition(
      name: "fetchBlogPost",
      description: "Fetch a Point-Free Pointers blog post as markdown with code blocks. Accepts a post number (228), slug (228-lazystate-1-0-now-available-to-everyone) or URL. No login needed.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "post":{"type":"string","description":"Post number, slug, or pointfree.co/blog/posts URL"}
      },"required":["post"]}
      """
    ),
    ToolDefinition(
      name: "login",
      description: "Sign in to pointfree.co with GitHub to access members-only transcripts. Opens a browser window on this Mac; the user completes the login there. Reports the current session if already signed in; pass force=true to sign in again.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "force":{"type":"boolean","description":"Re-authenticate even if a session exists"}
      }}
      """
    ),
  ]
}
