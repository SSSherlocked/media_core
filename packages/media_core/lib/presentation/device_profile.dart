/// Device profile categorization for playback presentation.
///
/// Used by the presentation manager to determine how to render media
/// on different screen types (e.g., force vertical on phones, responsive on tablets).
enum DeviceProfile {
  /// Standard smartphone. Typically forces vertical orientation for most content.
  mobile,

  /// Tablet or foldables. Supports responsive multi-column or side-by-side layouts.
  tablet,

  /// Desktop monitors. Focuses on windowed or fullscreen maximized layouts.
  desktop,
}
