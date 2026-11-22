import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let badNotesUndo = Notification.Name("badNotesUndo")
    static let badNotesRedo = Notification.Name("badNotesRedo")
    static let badNotesTogglePicker = Notification.Name("badNotesTogglePicker")
    static let badNotesSaveAll = Notification.Name("badNotesSaveAll") }

enum NoteTools {
    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    /// 원본은 그대로, 필기 합친 새 PDF를 temp에 만듦
    static func export(_ src: URL) -> URL? {
        NotificationCenter.default.post(name: .badNotesSaveAll, object: nil)
        guard let doc = PDFDocument(url: src) else { AppLog.shared.error("내보내기: PDF 열기 실패"); return nil }
        let name = src.deletingPathExtension().lastPathComponent
        let notes = src.deletingPathExtension().appendingPathExtension("notes")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-필기.pdf")
        try? FileManager.default.removeItem(at: out)
        let first = doc.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        let r = UIGraphicsPDFRenderer(bounds: first)
        do {
            try r.writePDF(to: out) { ctx in
                for i in 0..<doc.pageCount {
                    autoreleasepool {
                        guard let page = doc.page(at: i) else { return }
                        let box = page.bounds(for: .mediaBox)
                        let rect = CGRect(origin: .zero, size: box.size)
                        ctx.beginPage(withBounds: rect, pageInfo: [:])
                        let g = ctx.cgContext
                        g.saveGState()
                        g.translateBy(x: 0, y: rect.height); g.scaleBy(x: 1, y: -1)
                        page.draw(with: .mediaBox, to: g)
                        g.restoreGState()
                        let f = notes.appendingPathComponent("page\(i).drawing")
                        if let d = try? Data(contentsOf: f) {
                            do {
                                let dr = try PKDrawing(data: d)
                                dr.image(from: rect, scale: 2).draw(in: rect)
                            } catch { AppLog.shared.error("내보내기: 필기 읽기 실패 (\(i + 1)쪽): \(error.localizedDescription)") }
                        }
                    }
                }
            }
            AppLog.shared.info("내보냄: \(out.lastPathComponent)")
            return out
        } catch {
            AppLog.shared.error("내보내기 실패: \(error.localizedDescription)")
            return nil
        }
    }

    static func newNote(in dir: URL? = nil) -> URL? {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = (dir ?? docs).appendingPathComponent("새노트-\(f.string(from: Date())).pdf")
        let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
        do {
            try UIGraphicsPDFRenderer(bounds: a4).writePDF(to: url) { $0.beginPage() }
            AppLog.shared.info("새 노트: \(url.lastPathComponent)")
            return url
        } catch { AppLog.shared.error("새 노트 실패: \(error.localizedDescription)"); return nil }
    }

    static func appendPage(_ doc: PDFDocument, url: URL) -> Bool {
        let pg = PDFPage()
        pg.setBounds(CGRect(x: 0, y: 0, width: 595, height: 842), for: .mediaBox)
        doc.insert(pg, at: doc.pageCount)
        guard doc.write(to: url) else { AppLog.shared.error("쪽 추가: 저장 실패"); return false }
        return true
    }

    static func appendPage(_ url: URL) -> Bool {
        guard let doc = PDFDocument(url: url) else { AppLog.shared.error("쪽 추가: 열기 실패"); return false }
        doc.insert(PDFPage(), at: doc.pageCount)
        if let p = doc.page(at: doc.pageCount - 1) { p.setBounds(CGRect(x: 0, y: 0, width: 595, height: 842), for: .mediaBox) }
        guard doc.write(to: url) else { AppLog.shared.error("쪽 추가: 저장 실패"); return false }
        return true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct DocBrowser: UIViewControllerRepresentable {
    let onOpen: (URL) -> Void
    func makeCoordinator() -> Coord { Coord(onOpen) }
    func makeUIViewController(context: Context) -> UIDocumentBrowserViewController {
        let vc = UIDocumentBrowserViewController(forOpening: [.pdf])
        vc.allowsDocumentCreation = true
        vc.allowsPickingMultipleItems = false
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIDocumentBrowserViewController, context: Context) {}

    final class Coord: NSObject, UIDocumentBrowserViewControllerDelegate {
        let onOpen: (URL) -> Void
        init(_ o: @escaping (URL) -> Void) { onOpen = o }
        func documentBrowser(_ c: UIDocumentBrowserViewController, didPickDocumentsAt urls: [URL]) {
            if let u = urls.first { onOpen(u) }
        }
        func documentBrowser(_ c: UIDocumentBrowserViewController, didRequestDocumentCreationWithHandler handler: @escaping (URL?, UIDocumentBrowserViewController.ImportMode) -> Void) {
            handler(NoteTools.newNote(in: FileManager.default.temporaryDirectory), .move)
        }
        func documentBrowser(_ c: UIDocumentBrowserViewController, didImportDocumentAt src: URL, toDestinationURL dst: URL) { onOpen(dst) }
        func documentBrowser(_ c: UIDocumentBrowserViewController, failedToImportDocumentAt url: URL, error: Error?) {
            AppLog.shared.error("새 문서 가져오기 실패: \(error?.localizedDescription ?? "?")")
        }
    }
}
