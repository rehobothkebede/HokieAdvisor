import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Turns picked photos and files into what the chat function accepts:
/// photos become a downscaled JPEG, PDFs and text files become extracted text.
/// The limits mirror the chat Edge Function's checks.
nonisolated enum ChatAttachmentProcessor {
    static let maxImageDimension: CGFloat = 1600
    static let maxImageBytes = 1_500_000
    static let maxDocumentCharacters = 20_000
    static let maxPDFPages = 30

    enum ProcessingError: LocalizedError {
        case unreadableImage
        case imageTooLarge
        case unreadableFile
        case pdfWithoutText
        case unsupportedType(String)

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                return "Could not read that photo. Try another one."
            case .imageTooLarge:
                return "That photo is too large to send (max 1.5 MB after compression). Try cropping it."
            case .unreadableFile:
                return "Could not open that file."
            case .pdfWithoutText:
                return "This PDF has no selectable text (it may be a scan). Attach a photo of the page instead."
            case .unsupportedType(let name):
                return "\(name) isn't supported. Attach a photo, a PDF, or a text file."
            }
        }
    }

    struct Prepared {
        let payload: ChatAttachmentPayload
        let thumbnail: UIImage?
        let summary: String
    }

    // MARK: - Photos

    static func prepareImage(_ image: UIImage, name: String) throws -> Prepared {
        let scaled = downscaled(image)
        var data = scaled.jpegData(compressionQuality: 0.8)
        if let first = data, first.count > maxImageBytes {
            data = scaled.jpegData(compressionQuality: 0.6)
        }
        guard let data else { throw ProcessingError.unreadableImage }
        guard data.count <= maxImageBytes else { throw ProcessingError.imageTooLarge }

        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        return Prepared(
            payload: ChatAttachmentPayload(
                type: .image,
                name: jpegName(name),
                mimeType: "image/jpeg",
                dataBase64: data.base64EncodedString()
            ),
            thumbnail: scaled,
            summary: "\(Int(scaled.size.width))×\(Int(scaled.size.height)), \(size)"
        )
    }

    static func prepareImageData(_ data: Data, name: String) throws -> Prepared {
        guard let image = UIImage(data: data) else { throw ProcessingError.unreadableImage }
        return try prepareImage(image, name: name)
    }

    /// Scales so the longer side is at most maxImageDimension, rendering at 1x
    /// so pixel size (not points × screen scale) is what is capped.
    static func downscaled(_ image: UIImage) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        let ratio = longest > maxImageDimension ? maxImageDimension / longest : 1
        let target = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Files

    static func prepareFile(at url: URL) throws -> Prepared {
        let name = url.lastPathComponent
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data

        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(url: url) else { throw ProcessingError.unreadableFile }
            return try preparePDF(document, name: name)
        }
        if type.conforms(to: .image) {
            guard let data = try? Data(contentsOf: url) else { throw ProcessingError.unreadableFile }
            return try prepareImageData(data, name: name)
        }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) {
            guard let data = try? Data(contentsOf: url) else { throw ProcessingError.unreadableFile }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw ProcessingError.unreadableFile
            }
            return documentPrepared(name: name, text: text, pagesNote: nil)
        }
        throw ProcessingError.unsupportedType(name)
    }

    static func preparePDF(_ document: PDFDocument, name: String) throws -> Prepared {
        let pageCount = document.pageCount
        let pagesRead = min(pageCount, maxPDFPages)
        var pages: [String] = []
        for index in 0..<pagesRead {
            let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty { pages.append("[Page \(index + 1)]\n\(text)") }
        }
        guard !pages.isEmpty else { throw ProcessingError.pdfWithoutText }

        let note = pageCount > pagesRead ? "Only the first \(pagesRead) of \(pageCount) pages were included." : nil
        return documentPrepared(name: name, text: pages.joined(separator: "\n\n"), pagesNote: note)
    }

    private static func documentPrepared(name: String, text: String, pagesNote: String?) -> Prepared {
        let cleaned = text.replacingOccurrences(of: "\u{0}", with: "")
        var body = String(cleaned.prefix(maxDocumentCharacters))
        var notes = pagesNote.map { [$0] } ?? []
        if cleaned.count > maxDocumentCharacters {
            notes.append("Text was cut off after \(maxDocumentCharacters.formatted()) characters.")
        }
        if !notes.isEmpty { body += "\n\n[\(notes.joined(separator: " "))]" }

        return Prepared(
            payload: ChatAttachmentPayload(type: .document, name: name, text: body),
            thumbnail: nil,
            summary: "\(min(cleaned.count, maxDocumentCharacters).formatted()) characters of text"
                + (notes.isEmpty ? "" : ", truncated")
        )
    }

    private static func jpegName(_ name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return (base.isEmpty ? "Photo" : base) + ".jpg"
    }
}
