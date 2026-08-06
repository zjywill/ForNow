import ForNowCore
import Foundation

public struct ValidatedCustomURLTemplate: Equatable, Sendable {
  public static let currentVersion = 1
  public static let maximumTemplateBytes = 4_096
  public static let maximumURLBytes = 8_192
  public static let allowedSchemes: Set<String> = [
    "bear", "craft", "dayone", "drafts", "obsidian", "shortcuts", "things", "ulysses",
    "x-drafts",
  ]

  private enum Placeholder: String, CaseIterable {
    case content = "{CONTENT}"
    case title = "{TITLE}"
    case date = "{DATE}"

    var token: String {
      switch self {
      case .content: "FORNOWCONTENTPLACEHOLDER7F63A4"
      case .title: "FORNOWTITLEPLACEHOLDER7F63A4"
      case .date: "FORNOWDATEPLACEHOLDER7F63A4"
      }
    }
  }

  public let version: Int
  public let source: String

  public init(version: Int = currentVersion, source: String) throws {
    guard version == Self.currentVersion else {
      throw ExportError.invalidTemplate("Only template version 1 is supported.")
    }
    guard source.utf8.count <= Self.maximumTemplateBytes else {
      throw ExportError.oversizedTemplate(maximumBytes: Self.maximumTemplateBytes)
    }
    guard !source.isEmpty else {
      throw ExportError.invalidTemplate("Enter a URL template.")
    }
    try Self.validatePlaceholderSyntax(in: source)
    let tokenized = Self.tokenized(source)
    guard let components = URLComponents(string: tokenized),
      let scheme = components.scheme?.lowercased(),
      Self.allowedSchemes.contains(scheme)
    else {
      throw ExportError.invalidTemplate("Use an approved absolute application URL scheme.")
    }
    try Self.validatePlaceholderLocations(in: components, original: source)
    self.version = version
    self.source = source
  }

  public func render(document: ExportDocument) throws -> URL {
    var components = URLComponents(string: Self.tokenized(source))
    guard components != nil else {
      throw ExportError.invalidTemplate("The URL could not be parsed.")
    }
    let values: [Placeholder: String] = [
      .content: document.content,
      .title: document.title ?? "",
      .date: Self.dateString(document.exportedAt),
    ]

    var path = components?.percentEncodedPath ?? ""
    for placeholder in Placeholder.allCases {
      let rawValue = values[placeholder] ?? ""
      let compatibleValue =
        placeholder == .content
        ? rawValue.replacingOccurrences(of: "&", with: "+")
          .replacingOccurrences(of: "%", with: " percent")
        : rawValue
      guard let encoded = Self.percentEncodePathSegment(compatibleValue) else {
        throw ExportError.invalidTemplate("A path value could not be encoded.")
      }
      path = path.replacingOccurrences(of: placeholder.token, with: encoded)
    }
    components?.percentEncodedPath = path

    if var queryItems = components?.queryItems {
      queryItems = queryItems.map { item in
        URLQueryItem(
          name: item.name,
          value: Self.substitute(item.value ?? "", values: values)
        )
      }
      if var unwrappedComponents = components {
        try StrictURLQueryEncoder.apply(queryItems, to: &unwrappedComponents)
        components = unwrappedComponents
      }
    }

    if var fragment = components?.percentEncodedFragment {
      for placeholder in Placeholder.allCases {
        let rawValue = values[placeholder] ?? ""
        guard let encoded = Self.percentEncodeFragment(rawValue) else {
          throw ExportError.invalidTemplate("A fragment value could not be encoded.")
        }
        fragment = fragment.replacingOccurrences(of: placeholder.token, with: encoded)
      }
      components?.percentEncodedFragment = fragment
    }

    guard let url = components?.url else {
      throw ExportError.invalidTemplate("The rendered URL could not be constructed.")
    }
    guard url.absoluteString.utf8.count <= Self.maximumURLBytes else {
      throw ExportError.oversizedURL(maximumBytes: Self.maximumURLBytes)
    }
    return url
  }

  public static func diagnostic(for source: String) -> ExportDestinationDiagnostic {
    do {
      _ = try ValidatedCustomURLTemplate(source: source)
      return ExportDestinationDiagnostic(status: .available, message: "Template is valid.")
    } catch {
      return ExportDestinationDiagnostic(
        status: .requiresConfiguration,
        message: error.localizedDescription
      )
    }
  }

  private static func tokenized(_ source: String) -> String {
    Placeholder.allCases.reduce(source) { result, placeholder in
      result.replacingOccurrences(of: placeholder.rawValue, with: placeholder.token)
    }
  }

  private static func substitute(
    _ source: String,
    values: [Placeholder: String]
  ) -> String {
    Placeholder.allCases.reduce(source) { result, placeholder in
      result.replacingOccurrences(of: placeholder.token, with: values[placeholder] ?? "")
    }
  }

  private static func validatePlaceholderSyntax(in source: String) throws {
    for placeholder in Placeholder.allCases where source.contains(placeholder.token) {
      throw ExportError.invalidTemplate("The template contains a reserved token.")
    }
    var index = source.startIndex
    while index < source.endIndex {
      if source[index] == "{" {
        guard let closing = source[index...].firstIndex(of: "}") else {
          throw ExportError.invalidTemplate("A placeholder is missing its closing brace.")
        }
        let candidate = String(source[index...closing])
        guard Placeholder.allCases.contains(where: { $0.rawValue == candidate }) else {
          throw ExportError.invalidTemplate(
            "Only CONTENT, TITLE, and DATE placeholders are allowed.")
        }
        index = source.index(after: closing)
      } else if source[index] == "}" {
        throw ExportError.invalidTemplate("A placeholder has an unmatched closing brace.")
      } else {
        index = source.index(after: index)
      }
    }
  }

  private static func validatePlaceholderLocations(
    in components: URLComponents,
    original: String
  ) throws {
    let forbiddenComponents = [
      components.scheme ?? "", components.user ?? "", components.password ?? "",
      components.host ?? "",
    ]
    guard !forbiddenComponents.contains(where: containsToken) else {
      throw ExportError.invalidTemplate(
        "Placeholders are allowed only in path, query values, or fragment."
      )
    }
    if let queryItems = components.queryItems,
      queryItems.contains(where: { containsToken($0.name) })
    {
      throw ExportError.invalidTemplate("A placeholder cannot be a query parameter name.")
    }
    let allowedArea = components.path + (components.query ?? "") + (components.fragment ?? "")
    for placeholder in Placeholder.allCases {
      let expected = original.components(separatedBy: placeholder.rawValue).count - 1
      let actual = allowedArea.components(separatedBy: placeholder.token).count - 1
      guard expected == actual else {
        throw ExportError.invalidTemplate(
          "Placeholders are allowed only in path, query values, or fragment."
        )
      }
    }
  }

  private static func containsToken(_ value: String) -> Bool {
    Placeholder.allCases.contains { value.contains($0.token) }
  }

  private static func percentEncodePathSegment(_ value: String) -> String? {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#%;&=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed)
  }

  private static func percentEncodeFragment(_ value: String) -> String? {
    var allowed = CharacterSet.urlFragmentAllowed
    allowed.remove(charactersIn: "%#")
    return value.addingPercentEncoding(withAllowedCharacters: allowed)
  }

  private static func dateString(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      parts.year ?? 0,
      parts.month ?? 0,
      parts.day ?? 0
    )
  }
}

public struct CustomURLExportDestination: ExportDestination, Sendable {
  private let template: ValidatedCustomURLTemplate
  private let opener: any ExternalURLOpening

  public init(
    template: ValidatedCustomURLTemplate,
    opener: any ExternalURLOpening
  ) {
    self.template = template
    self.opener = opener
  }

  public func export(_ document: ExportDocument) async throws -> ExportReceipt {
    let url = try template.render(document: document)
    guard await opener.isAvailable(for: url) else {
      throw ExportError.destinationUnavailable(
        name: url.scheme ?? "Custom destination",
        guidance: "Install the destination application or update the custom URL template."
      )
    }
    guard await opener.open(url) else {
      throw ExportError.openFailed(url.scheme ?? "Custom destination")
    }
    return ExportReceipt(
      destination: .customURL,
      resource: .externalURL(url),
      exportedAt: document.exportedAt
    )
  }
}
