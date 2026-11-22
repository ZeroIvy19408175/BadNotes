//
//  ContentView.swift
//  BadNotes
//
//  원본 PDF는 앱 폴더로 복사만 하고 다시 쓰지 않음.
//  필기는 <파일이름>.notes/pageN.drawing 에 페이지별로 atomic 저장.
//

import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var pdfURL: URL?
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if let url = pdfURL {
                    PDFNoteView(url: url)
                        .id(url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("PDF를 열어 주세요",
                                           systemImage: "doc.richtext",
                                           description: Text("오른쪽 위 '열기'를 누르세요"))
                }
            }
            .navigationTitle(pdfURL?.deletingPathExtension().lastPathComponent ?? "BadNotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("열기") { showImporter = true }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.pdf]) { result in
                guard case .success(let src) = result else { return }
                let ok = src.startAccessingSecurityScopedResource()
                defer { if ok { src.stopAccessingSecurityScopedResource() } }
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let dst = docs.appendingPathComponent(src.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dst.path) {
                    do { try FileManager.default.copyItem(at: src, to: dst) }
                    catch { print("복사 실패: \(error)"); return }
                }
                pdfURL = dst
            }
        }
    }
}

struct PDFNoteView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(pdfURL: url) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageOverlayViewProvider = context.coordinator
        view.document = PDFDocument(url: url)
        view.isInMarkupMode = true
        context.coordinator.pdfView = view
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.saveAll()
    }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider {
        let pdfURL: URL
        let toolPicker = PKToolPicker()
        weak var pdfView: PDFView?
        var canvases: [Int: PKCanvasView] = [:]

        init(pdfURL: URL) {
            self.pdfURL = pdfURL
            super.init()
            // 앱이 백그라운드로 가면 열려 있는 페이지 필기 저장
            NotificationCenter.default.addObserver(self, selector: #selector(saveAllNow),
                                                   name: UIApplication.willResignActiveNotification,
                                                   object: nil)
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        var notesDir: URL {
            let dir = pdfURL.deletingPathExtension().appendingPathExtension("notes")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        func drawingURL(_ page: Int) -> URL {
            notesDir.appendingPathComponent("page\(page).drawing")
        }

        func save(_ canvas: PKCanvasView, page: Int) {
            do {
                try canvas.drawing.dataRepresentation()
                    .write(to: drawingURL(page), options: .atomic)
            } catch {
                print("필기 저장 실패 page \(page): \(error)")
            }
        }

        @objc func saveAllNow() { saveAll() }

        func saveAll() {
            for (page, canvas) in canvases { save(canvas, page: page) }
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            guard let doc = view.document else { return nil }
            let index = doc.index(for: page)
            if let existing = canvases[index] { return existing }

            let canvas = PKCanvasView()
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.drawingPolicy = .pencilOnly   // 손가락은 스크롤, 펜만 필기
            if let data = try? Data(contentsOf: drawingURL(index)),
               let drawing = try? PKDrawing(data: data) {
                canvas.drawing = drawing
            }
            toolPicker.setVisible(true, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
            canvases[index] = canvas
            return canvas
        }

        func pdfView(_ view: PDFView, willEndDisplayingOverlayView overlay: UIView, for page: PDFPage) {
            guard let canvas = overlay as? PKCanvasView,
                  let doc = view.document else { return }
            let index = doc.index(for: page)
            save(canvas, page: index)
            toolPicker.removeObserver(canvas)
            canvases[index] = nil
        }
    }
}

#Preview {
    ContentView()
}
