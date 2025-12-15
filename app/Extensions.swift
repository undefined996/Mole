import AppKit

extension Bundle {
  /// Loads an image from the bundle's resources by name.
  ///
  /// This method attempts to load an image with the given name by trying
  /// common image file extensions in order: PNG, JPG, and ICNS.
  ///
  /// - Parameter name: The name of the image resource without extension.
  /// - Returns: An NSImage if found, nil otherwise.
  ///
  /// - Note: Supported formats: PNG, JPG, ICNS
  func image(forResource name: String) -> NSImage? {
    if let url = url(forResource: name, withExtension: "png") { return NSImage(contentsOf: url) }
    if let url = url(forResource: name, withExtension: "jpg") { return NSImage(contentsOf: url) }
    if let url = url(forResource: name, withExtension: "icns") { return NSImage(contentsOf: url) }
    return nil
  }
}
