import PDFKit
import SwiftUI

/// Shows the original uploaded page, with the supporting excerpt highlighted
/// when it can be located in the PDF's text.
struct SyllabusPageView: View {
    @EnvironmentObject private var store: CourseCompanionStore
    @Environment(\.dismiss) private var dismiss
    let documentId: String
    let mimeType: String
    let page: Int
    let excerpt: String?

    @State private var data: Data?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let data {
                    if mimeType == "application/pdf" {
                        PDFPageRepresentable(data: data, page: page, excerpt: excerpt)
                            .ignoresSafeArea(edges: .bottom)
                    } else if let image = UIImage(data: data) {
                        ScrollView([.vertical, .horizontal]) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .accessibilityLabel("Uploaded syllabus image")
                        }
                    }
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary).padding()
                } else {
                    ProgressView("Opening your syllabus…")
                }
            }
            .navigationTitle("Page \(page)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if let excerpt {
                    Text("“\(excerpt)”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(AgoraSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                        .accessibilityLabel("Supporting text: \(excerpt)")
                }
            }
        }
        .task {
            do { data = try await store.documentFile(documentId) } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct PDFPageRepresentable: UIViewRepresentable {
    let data: Data
    let page: Int
    let excerpt: String?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        if let document = PDFDocument(data: data) {
            view.document = document
            if let target = document.page(at: max(0, page - 1)) {
                view.go(to: target)
                if let selection = Self.selection(for: excerpt, in: document, on: target) {
                    selection.color = UIColor.systemYellow.withAlphaComponent(0.45)
                    view.highlightedSelections = [selection]
                    view.go(to: selection)
                }
            }
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}

    /// Finds the excerpt's opening words on the cited page (PDF text can wrap
    /// differently, so a short prefix is the most reliable anchor).
    private static func selection(for excerpt: String?, in document: PDFDocument, on page: PDFPage) -> PDFSelection? {
        guard let excerpt else { return nil }
        let words = excerpt.split(whereSeparator: \.isWhitespace)
        for count in [8, 5, 3] where words.count >= count {
            let needle = words.prefix(count).joined(separator: " ")
            if let match = document.findString(needle, withOptions: [.caseInsensitive]).first(where: { $0.pages.contains(page) }) {
                return match
            }
        }
        return nil
    }
}
