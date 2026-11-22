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
    @State private var showLog = false
    @State private var page = 0
    @State private var pageCount = 0
    @State private var jumpTarget: Int?
    @State private var showJump = false
    @State private var shareURL: URL?
    @State private var jumpText = ""
    var log = AppLog.shared

    var body: some View {
        if let url = pdfURL {
            editor(url)
        } else {
            DocBrowser(onOpen: { open($0) })
                .ignoresSafeArea()
        }
    }

    func editor(_ url: URL) -> some View {
        ZStack(alignment: .top) {
            PDFNoteView(url: url, jumpTarget: $jumpTarget,
                        onPage: { p, c in page = p; pageCount = c })
                .id(url.path)
                .ignoresSafeArea(edges: .top)
            topBar(url)
        }
        .overlay(alignment: .bottom) { errorBanner }
        .sheet(isPresented: $showLog) { LogView() }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let u = shareURL { ShareSheet(url: u) }
        }
        .alert("페이지 이동", isPresented: $showJump) {
            TextField("1 ~ \(pageCount)", text: $jumpText).keyboardType(.numberPad)
            Button("이동") {
                if let n = Int(jumpText), (1...pageCount).contains(n) { jumpTarget = n - 1 }
                else { log.warn("잘못된 페이지 번호: \(jumpText)") }
            }
            Button("취소", role: .cancel) {}
        }
    }

    /// 44pt 터치 영역, 아이콘 18pt (HIG 최소 44x44)
    func icon(_ name: String, tint: Color = .primary, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }

    func capsule<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 0) { content() }
            .padding(.horizontal, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    func topBar(_ url: URL) -> some View {
        HStack(spacing: 12) {
            capsule {
                icon("arrow.down.right.and.arrow.up.left") {
                    NotificationCenter.default.post(name: .badNotesSaveAll, object: nil)
                    pdfURL = nil
                }
                icon("arrow.uturn.backward.circle") { NotificationCenter.default.post(name: .badNotesUndo, object: nil) }
                icon("arrow.uturn.forward.circle") { NotificationCenter.default.post(name: .badNotesRedo, object: nil) }
            }
            Spacer(minLength: 0)
            Button {
                guard pageCount > 0 else { return }
                jumpText = ""; showJump = true
            } label: {
                VStack(spacing: 0) {
                    Text(url.deletingPathExtension().lastPathComponent).font(.subheadline.bold()).lineLimit(1)
                    if pageCount > 0 {
                        Text("\(page + 1) / \(pageCount) 쪽").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .frame(maxWidth: 320)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            capsule {
                icon("square.and.arrow.up") { shareURL = NoteTools.export(url) }
                icon("pencil.tip.crop.circle") { NotificationCenter.default.post(name: .badNotesTogglePicker, object: nil) }
                Menu {
                    Button { showLog = true } label: { Label("로그", systemImage: "ladybug") }
                    Button {
                        guard pageCount > 0 else { return }
                        jumpText = ""; showJump = true
                    } label: { Label("페이지 이동", systemImage: "arrow.right.doc.on.clipboard") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(log.unreadErrors > 0 ? Color.red : Color.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                icon("square.and.pencil") {
                    NotificationCenter.default.post(name: .badNotesSaveAll, object: nil)
                    if let n = NoteTools.newNote() { pdfURL = n }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder var errorBanner: some View {
        if let e = log.latestError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("오류").font(.subheadline.bold())
                    Text(e.message).font(.caption).lineLimit(3)
                }
                Spacer()
                Button("로그") { showLog = true }.buttonStyle(.bordered).tint(.white)
                Button { log.markRead() } label: { Image(systemName: "xmark") }
                    .tint(.white)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.red.gradient, in: RoundedRectangle(cornerRadius: 14))
            .padding()
        }
    }

    /// 앱 Documents 안이면 그대로, 밖이면 한 번 복사(원본 불변)
    func open(_ src: URL) {
        let ok = src.startAccessingSecurityScopedResource()
        defer { if ok { src.stopAccessingSecurityScopedResource() } }
        let docs = NoteTools.docs.resolvingSymlinksInPath().path
        if src.resolvingSymlinksInPath().path.hasPrefix(docs + "/") { pdfURL = src; return }
        let dst = NoteTools.docs.appendingPathComponent(src.lastPathComponent)
        if !FileManager.default.fileExists(atPath: dst.path) {
            do { try FileManager.default.copyItem(at: src, to: dst); log.info("앱 폴더로 복사함: \(dst.lastPathComponent)") }
            catch { log.error("PDF 복사 실패: \(error.localizedDescription)"); return }
        }
        pdfURL = dst
    }
}

struct PDFNoteView: UIViewRepresentable {
    let url: URL
    @Binding var jumpTarget: Int?
    var onPage: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(pdfURL: url, onPage: onPage)
    }

    func makeUIView(context: Context) -> PDFView {
        let c = context.coordinator
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .systemGroupedBackground
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageOverlayViewProvider = c
        if let doc = PDFDocument(url: url) {
            view.document = doc
            AppLog.shared.info("열림: \(url.lastPathComponent) (\(doc.pageCount)쪽)")
        } else {
            AppLog.shared.error("PDF를 열 수 없음(손상됐거나 암호 걸림): \(url.lastPathComponent)")
        }
        view.isInMarkupMode = true
        c.pdfView = view
        c.attach()
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if let t = jumpTarget, let page = uiView.document?.page(at: t) {
            uiView.go(to: page)
            DispatchQueue.main.async { jumpTarget = nil }
        }
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.saveAll()
    }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider {
        let pdfURL: URL
        let onPage: (Int, Int) -> Void
        let toolPicker = PKToolPicker()
        weak var pdfView: PDFView?
        var canvases: [Int: PKCanvasView] = [:]
        private var offsetObs: NSKeyValueObservation?

        init(pdfURL: URL, onPage: @escaping (Int, Int) -> Void) {
            self.pdfURL = pdfURL
            self.onPage = onPage
            super.init()
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(undo), name: .badNotesUndo, object: nil)
            nc.addObserver(self, selector: #selector(redo), name: .badNotesRedo, object: nil)
            nc.addObserver(self, selector: #selector(togglePicker), name: .badNotesTogglePicker, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(saveAllNow),
                                                   name: .badNotesSaveAll, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(saveAllNow),
                                                   name: UIApplication.willResignActiveNotification,
                                                   object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            offsetObs?.invalidate()
        }

        func attach() {
            guard let view = pdfView else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged),
                                                   name: .PDFViewPageChanged, object: view)
            NotificationCenter.default.addObserver(self, selector: #selector(reassertToolPicker),
                                                   name: .PDFViewScaleChanged, object: view)
            pageChanged()
            DispatchQueue.main.async { [weak self] in
                guard let self, let sv = self.findScrollView(in: view) else {
                    AppLog.shared.warn("스크롤뷰를 못 찾아 쪽 추가 당기기가 꺼짐")
                    return
                }
                // 캡슐 줄 밑으로 스크롤되되 1쪽 위쪽은 가리지 않게 상단 여백
                let top = 60 + (view.window?.safeAreaInsets.top ?? 0)
                sv.contentInset.top = top
                sv.verticalScrollIndicatorInsets.top = top
                sv.contentOffset.y = -top
                self.offsetObs = sv.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                    guard let self else { return }
                    let maxY = max(-sv.adjustedContentInset.top,
                                   sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
                    if sv.isTracking {
                        if sv.contentOffset.y > maxY + 80 { self.armed = true }
                    } else if self.armed {
                        self.armed = false
                        let now = CACurrentMediaTime()
                        if now - self.lastAdd > 1.5 { self.lastAdd = now; self.addPage() }
                    }
                }
            }
        }

        func addPage() {
            guard pdfURL.lastPathComponent.hasPrefix("새노트-") else {
                AppLog.shared.info("가져온 PDF에는 쪽을 추가하지 않음")
                return
            }
            guard let doc = pdfView?.document else { return }
            saveAll()
            if NoteTools.appendPage(doc, url: pdfURL) {
                AppLog.shared.info("쪽 추가: \(doc.pageCount)쪽")
                onPage(pdfView?.currentPage.map { doc.index(for: $0) } ?? 0, doc.pageCount)
            }
        }

        var armed = false
        var lastAdd: CFTimeInterval = 0
        var pickerOn = true

        func currentCanvas() -> PKCanvasView? {
            guard let view = pdfView, let doc = view.document else { return nil }
            let cur = view.currentPage.map { doc.index(for: $0) }
            return cur.flatMap { canvases[$0] }
        }
        @objc func undo() { currentCanvas()?.undoManager?.undo() }
        @objc func redo() { currentCanvas()?.undoManager?.redo() }
        @objc func togglePicker() {
            pickerOn.toggle()
            if pickerOn { reassertToolPicker() }
            else if let c = currentCanvas() { toolPicker.setVisible(false, forFirstResponder: c); c.resignFirstResponder() }
        }

        func findScrollView(in v: UIView) -> UIScrollView? {
            if let s = v as? UIScrollView { return s }
            for sub in v.subviews { if let s = findScrollView(in: sub) { return s } }
            return nil
        }

        @objc func pageChanged() {
            guard let view = pdfView, let doc = view.document,
                  let cur = view.currentPage else { return }
            onPage(doc.index(for: cur), doc.pageCount)
            reassertToolPicker()
        }

        /// 줌/재배치로 캔버스가 바뀌면 first responder가 빠져 도구 팔레트가 사라짐.
        /// 화면에 붙어 있는 현재 페이지 캔버스에 다시 붙여 줌.
        @objc func reassertToolPicker() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pickerOn, let view = self.pdfView, let doc = view.document else { return }
                let cur = view.currentPage.map { doc.index(for: $0) }
                let target = cur.flatMap { self.canvases[$0] }.flatMap { $0.window != nil ? $0 : nil }
                    ?? self.canvases.values.first { $0.window != nil }
                guard let canvas = target else { return }
                if !canvas.isFirstResponder {
                    self.toolPicker.setVisible(true, forFirstResponder: canvas)
                    self.toolPicker.addObserver(canvas)
                    if !canvas.becomeFirstResponder() {
                        AppLog.shared.warn("필기 도구 다시 붙이기 실패")
                    }
                }
            }
        }

        var notesDir: URL {
            let dir = pdfURL.deletingPathExtension().appendingPathExtension("notes")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                AppLog.shared.error("필기 폴더 생성 실패: \(error.localizedDescription)")
            }
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
                AppLog.shared.error("필기 저장 실패 (\(page + 1)쪽): \(error.localizedDescription)")
            }
        }

        @objc func saveAllNow() { saveAll() }

        func saveAll() {
            guard !canvases.isEmpty else { return }
            for (page, canvas) in canvases { save(canvas, page: page) }
            AppLog.shared.info("열린 페이지 \(canvases.count)개 저장")
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            guard let doc = view.document else { return nil }
            let index = doc.index(for: page)
            if let existing = canvases[index] { return existing }

            let canvas = PKCanvasView()
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.drawingPolicy = .pencilOnly
            let file = drawingURL(index)
            if FileManager.default.fileExists(atPath: file.path) {
                do {
                    canvas.drawing = try PKDrawing(data: Data(contentsOf: file))
                } catch {
                    AppLog.shared.error("필기 불러오기 실패 (\(index + 1)쪽): \(error.localizedDescription)")
                }
            }
            toolPicker.setVisible(pickerOn, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            canvases[index] = canvas
            reassertToolPicker()
            return canvas
        }

        func pdfView(_ view: PDFView, willEndDisplayingOverlayView overlay: UIView, for page: PDFPage) {
            guard let canvas = overlay as? PKCanvasView,
                  let doc = view.document else { return }
            let index = doc.index(for: page)
            save(canvas, page: index)
            toolPicker.removeObserver(canvas)
            canvases[index] = nil
            reassertToolPicker()
        }
    }
}

#Preview {
    ContentView()
}
