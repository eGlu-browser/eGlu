import CoreGraphics
import Foundation
import ImageIO
import PadCore

/// A picture handed off, read on the device: its own facts (pixels, when
/// it was taken, camera and lens — never where, which is not read), a
/// thumbnail of it for Vision and the model, and the Markdown the file is
/// written from. Away from the main thread: a photo's decoding takes long.
nonisolated enum HandoffPicture {
    /// The picture for reading, at most 4096 on a side: the model and
    /// Vision need no more of it.
    static func thumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }

    /// Whether the bytes are a picture at all, by what they start with:
    /// ImageIO makes a source of any bytes, and knows a picture's kind.
    static func isPicture(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }

    /// The picture's own facts: its size, and from its EXIF and TIFF
    /// dictionaries when it was taken and the camera and lens. The GPS
    /// dictionary is never read, so no place is ever written.
    static func facts(_ data: Data, into given: FileFacts) -> FileFacts? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        var facts = given
        facts.width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        facts.height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            facts.taken = day(exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            facts.lens = exif[kCGImagePropertyExifLensModel] as? String
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let make = tiff[kCGImagePropertyTIFFMake] as? String ?? ""
            let model = tiff[kCGImagePropertyTIFFModel] as? String ?? ""
            // The model often carries the make already ("Canon EOS"): say it once.
            let camera = model.lowercased().hasPrefix(make.lowercased()) || make.isEmpty
                ? model : [make, model].joined(separator: " ")
            if !camera.isEmpty { facts.camera = camera }
        }
        return facts
    }

    /// "2026:10:02 14:33:12" as EXIF writes it to "2026-10-02".
    private static func day(_ said: String?) -> String? {
        guard let said, said.count >= 10 else { return nil }
        return said.prefix(10).replacingOccurrences(of: ":", with: "-")
    }

    /// The file's Markdown for the picture: its name for a heading, a
    /// Markdown picture with the model's description for its words where
    /// there was one, then the text read in it as paragraphs, or said to
    /// have none, or that Vision could not read it (`text` nil).
    static func markdown(name: String, description: String, text: String?) -> String {
        var parts = ["# \(name)", "![\(description)](\(name))"]
        if let text {
            parts.append(text.isEmpty ? String(localized: "No text in it.") : String(localized: "Text in the picture:") + "\n\n" + text)
        } else {
            parts.append(String(localized: "The text in it could not be read on this device."))
        }
        return parts.joined(separator: "\n\n")
    }
}
