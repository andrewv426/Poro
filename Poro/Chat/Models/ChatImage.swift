import Foundation

/// An image attached to a chat message. Holds downscaled JPEG bytes so it can be both rendered
/// (via `NSImage(data:)`) and sent to a vision model as an OpenAI/OpenRouter `image_url` part.
struct ChatImage: Identifiable, Equatable {
  let id: UUID
  let data: Data
  let mimeType: String

  init(data: Data, mimeType: String = "image/jpeg", id: UUID = UUID()) {
    self.id = id
    self.data = data
    self.mimeType = mimeType
  }

  /// Base64 data URL for the `image_url` content part: `data:image/jpeg;base64,<…>`.
  var dataURL: String {
    "data:\(mimeType);base64,\(data.base64EncodedString())"
  }
}
