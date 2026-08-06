import ForNowCore
import Foundation

enum StrictURLQueryEncoder {
  static func apply(_ queryItems: [URLQueryItem], to components: inout URLComponents) throws {
    let encodedItems = try queryItems.map { item in
      guard let name = encode(item.name) else {
        throw ExportError.invalidTemplate("A query value could not be encoded.")
      }
      let value: String?
      if let rawValue = item.value {
        guard let encodedValue = encode(rawValue) else {
          throw ExportError.invalidTemplate("A query value could not be encoded.")
        }
        value = encodedValue
      } else {
        value = nil
      }
      return URLQueryItem(name: name, value: value)
    }
    components.percentEncodedQueryItems = encodedItems
  }

  private static func encode(_ value: String) -> String? {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed)
  }
}
