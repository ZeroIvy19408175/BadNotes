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
    @State private var showLog = false
    @State private var barHidden = false
    @State private var page = 0
    @State private var pageCount = 0
    @State private var jumpTarget: Int?
    @State private var showJump = false
    @State private var jumpText = ""
    var log = AppLog.shared

    var body: some View {
        NavigationStack {
            Group {
                if let url = pdfURL {
                    PDFNoteView(url: url,
                                jumpTarget: $jumpTarget,
                                onPage: { p, c in page = p; pageCount = c },
                                onScrollHide: { hide in
                                    if hide != barHidden {
                                        withAnimation(.easeInOut(duration: 0.2)) { barHidden = hide }
                                    }
                                })
                        .id(url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("PDF를 열어 주세요",
                                           systemImage: "doc.richtext",
                                           description: Text("오른쪽 위 '열기'를 누르세요"))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(barHidden ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLog = true } label: {
                        Image(systemName: log.unreadErrors > 0
                              ? "exclamationmark.triangle.fill" : "ladybug")
                            .foregroundStyle(log.unreadErrors > 0 ? .red : .accentColor)
                    }
                    .accessibilityLabel("로그")
                }
                ToolbarItem(placement: .principal) {
                    // 제목 영역: 파일 이름 + 페이지. 누르면 페이지 이동
                    Button {
                        guard pageCount > 0 else { return }
                        jumpText = ""
                        showJump = true
                    } label: {
                        VStack(spacing: 0) {
                            Text(pdfURL?.deletingPathExtension().lastPathComponent ?? "BadNotes")
                                .font(.headline).lineLimit(1)
                            if pageCount > 0 {
                                Text("\(page + 1) / \(pageCount) 쪽")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("열기") { showImporter = true }
                }
            }
            .alert("페이지 이동", isPresented: $showJump) {
                TextField("1 ~ \(pageCount)", text: $jumpText).keyboardType(.numberPad)
                Button("이동") {
                    if let n = Int(jumpText), (1...pageCount).contains(n) {
                        jumpTarget = n - 1
                    } else {
                        log.warn("잘못된 페이지 번호: \(jumpText)")
                    }
                }
                Button("취소", role: .cancel) {}
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.pdf]) { result in
                open(result)
            }
            .sheet(isPresented: $showLog) { LogView() }
            .overlay(alignment: .bottom) { errorBanner }
            // 바가 숨었을 때 화면 위쪽을 탭하면 다시 보이게
            .overlay(alignment: .top) {
                if barHidden {
                    Color.clear.frame(height: 24).contentShape(Rectangle())
                        .onTapGesture { withAnimation { barHidden = false } }
                }
            }
        }
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
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring, value: e.id)
        }
    }

    func open(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let err):
            log.error("파일 선택 실패: \(err.localizedDescription)")
        case .success(let src):
            let ok = src.startAccessingSecurityScopedResource()
            defer { if ok { src.stopAccessingSecurityScopedResource() } }
            if !ok { log.warn("보안 범위 접근 실패(계속 시도): \(src.lastPathComponent)") }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dst = docs.appendingPathComponent(src.lastPathComponent)
            if FileManager.default.fileExists(atPath: dst.path) {
                log.info("기존 복사본 사용: \(dst.lastPathComponent)")
            } else {
                do {
                    try FileManager.default.copyItem(at: src, to: dst)
                    log.info("앱 폴더로 복사함: \(dst.lastPathComponent)")
                } catch {
                    log.error("PDF 복사 실패: \(error.localizedDescription)")
                    return
                }
            }
            barHidden = false
            pdfURL = dst
        }
    }
}

struct PDFNoteView: UIViewRepresentable {
    let url: URL
    @Binding var jumpTarget: Int?
    var onPage: (Int, Int) -> Void
    var onScrollHide: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(pdfURL: url, onPage: onPage, onScrollHide: onScrollHide)
    }

    func makeUIView(context: Context) -> PDFView {
        let c = context.coordinator
        let view = PDFView()
        view.autoScales = true
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
        let onScrollHide: (Bool) -> Void
        let toolPicker = PKToolPicker()
        weak var pdfView: PDFView?
        var canvases: [Int: PKCanvasView] = [:]
        private var offsetObs: NSKeyValueObservation?
        private var lastY: CGFloat = 0
        private var lastToggle: CFTimeInterval = 0
        private var barHidden = false

        init(pdfURL: URL, onPage: @escaping (Int, Int) -> Void, onScrollHide: @escaping (Bool) -> Void) {
            self.pdfURL = pdfURL
            self.onPage = onPage
            self.onScrollHide = onScrollHide
            super.init()
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
            // PDFView 안쪽 스크롤뷰를 찾아 스크롤 방향 감시
            DispatchQueue.main.async { [weak self] in
                guard let self, let sv = self.findScrollView(in: view) else {
                    AppLog.shared.warn("스크롤뷰를 못 찾아 상단바 자동 숨김이 꺼짐")
                    return
                }
                self.lastY = sv.contentOffset.y
                self.offsetObs = sv.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                    guard let self else { return }
                    let y = sv.contentOffset.y
                    let minY = -sv.adjustedContentInset.top
                    let maxY = max(minY, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
                    // 손가락으로 끌고 있을 때만 판정 (바 전환으로 인한 재배치·관성·튕김은 무시)
                    guard sv.isTracking else { self.lastY = y; return }
                    // 위/아래 끝을 넘어간 고무줄 구간은 무시
                    if y < minY || y > maxY { self.lastY = y; return }
                    let dy = y - self.lastY
                    if abs(dy) < 12 { return }
                    self.lastY = y
                    // 방금 바꿨으면 잠깐 다시 안 바꿈
                    let now = CACurrentMediaTime()
                    if now - self.lastToggle < 0.35 { return }
                    let hide = (y <= minY + 4) ? false : dy > 0
                    if hide != self.barHidden {
                        self.barHidden = hide
                        self.lastToggle = now
                        self.onScrollHide(hide)
                    }
                }
            }
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
                guard let self, let view = self.pdfView, let doc = view.document else { return }
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
            toolPicker.setVisible(true, forFirstResponder: canvas)
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
