import Foundation
import PDFKit
import UIKit
import Vision

/// Reads a syllabus's text page by page on this device: the PDF's own text
/// layer when it has one, otherwise on-device OCR (Vision). Only this text and
/// the original file are uploaded; the server checks every extracted fact
/// against these pages.
nonisolated enum SyllabusTextExtractor {
    static let maxPages = 60
    static let maxBytes = 10 * 1024 * 1024

    enum Method: String, Encodable {
        case pdfText = "pdf_text"
        case ocr
        case mixed
    }

    struct Page: Encodable {
        let page: Int
        let text: String
    }

    struct Result {
        let pages: [Page]
        let method: Method
    }

    enum ExtractionError: LocalizedError {
        case unsupportedType
        case tooLarge
        case unreadable
        case tooManyPages
        case noText

        var errorDescription: String? {
            switch self {
            case .unsupportedType: return "Choose a PDF, PNG, or JPEG file."
            case .tooLarge: return "The file must be smaller than 10 MB."
            case .unreadable: return "Agora couldn’t open that file."
            case .tooManyPages: return "Syllabi can have up to \(SyllabusTextExtractor.maxPages) pages."
            case .noText: return "Agora couldn’t read text in this file. Try a clearer copy or the original PDF."
            }
        }
    }

    static func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return nil
        }
    }

    static func extract(data: Data, mimeType: String) async throws -> Result {
        guard data.count <= maxBytes else { throw ExtractionError.tooLarge }
        switch mimeType {
        case "application/pdf":
            return try await extractPDF(data)
        case "image/png", "image/jpeg":
            guard let image = UIImage(data: data)?.cgImage else { throw ExtractionError.unreadable }
            let text = try await recognizeText(in: image)
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else { throw ExtractionError.noText }
            return Result(pages: [Page(page: 1, text: text)], method: .ocr)
        default:
            throw ExtractionError.unsupportedType
        }
    }

    private static func extractPDF(_ data: Data) async throws -> Result {
        guard let document = PDFDocument(data: data) else { throw ExtractionError.unreadable }
        guard document.pageCount >= 1 else { throw ExtractionError.unreadable }
        guard document.pageCount <= maxPages else { throw ExtractionError.tooManyPages }

        var pages: [Page] = []
        var usedText = false
        var usedOCR = false
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let layer = page.string ?? ""
            if layer.trimmingCharacters(in: .whitespacesAndNewlines).count >= 30 {
                pages.append(Page(page: index + 1, text: layer))
                usedText = true
            } else if let image = render(page) {
                pages.append(Page(page: index + 1, text: try await recognizeText(in: image)))
                usedOCR = true
            } else {
                pages.append(Page(page: index + 1, text: layer))
            }
        }
        let total = pages.reduce(0) { $0 + $1.text.trimmingCharacters(in: .whitespacesAndNewlines).count }
        guard total >= 80 else { throw ExtractionError.noText }
        let method: Method = usedOCR ? (usedText ? .mixed : .ocr) : .pdfText
        return Result(pages: pages, method: method)
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage
    }

    private static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
