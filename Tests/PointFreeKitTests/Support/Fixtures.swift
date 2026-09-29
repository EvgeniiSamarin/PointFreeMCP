import Foundation

func fixture(_ name: String) throws -> Data {
  let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
  guard let url else { throw FixtureError.missing(name) }
  return try Data(contentsOf: url)
}

func fixtureString(_ name: String) throws -> String {
  String(decoding: try fixture(name), as: UTF8.self)
}

enum FixtureError: Error { case missing(String) }
