import Foundation

public enum BlogFeedParser {
  public static func parse(xml: String) throws -> [BlogPost] {
    let delegate = AtomDelegate()
    let parser = XMLParser(data: Data(xml.utf8))
    parser.delegate = delegate
    guard parser.parse(), delegate.sawFeed else {
      throw PointFreeError.structureChanged("blog atom feed", URL(string: "https://www.pointfree.co/blog/feed/atom.xml"))
    }
    return delegate.posts
  }

  private final class AtomDelegate: NSObject, XMLParserDelegate {
    var posts: [BlogPost] = []
    var sawFeed = false
    private var inEntry = false
    private var currentElement = ""
    private var title = "", link = "", updated = "", content = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
      currentElement = name
      switch name {
      case "feed": sawFeed = true
      case "entry": inEntry = true; title = ""; link = ""; updated = ""; content = ""
      case "link" where inEntry: link = attributes["href"] ?? link
      default: break
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      guard inEntry else { return }
      switch currentElement {
      case "title": title += string
      case "updated": updated += string
      case "content": content += string
      default: break
      }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
      guard inEntry, currentElement == "content" else { return }
      content += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
      currentElement = ""
      guard name == "entry", inEntry else { return }
      inEntry = false
      guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)),
            let slug = url.pathComponents.last,
            let ref = BlogPostRef.parse(slug),
            let date = try? Date(updated.trimmingCharacters(in: .whitespacesAndNewlines), strategy: .iso8601)
      else { return }
      posts.append(BlogPost(number: ref.number, slug: slug, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            url: url, updated: date, contentHTML: content))
    }
  }
}
