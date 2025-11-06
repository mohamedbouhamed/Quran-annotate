//
//  QuranPageCurlView.swift
//  Quran annotate
//
//  Created by Macbook Air on 06/11/2025.
//

import SwiftUI
import UIKit
import PDFKit
import PencilKit

// ViewController vide pour accompagner la page 0
class EmptyPageViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }
}

// UIPageViewController avec page curl pour le Coran
class QuranPageCurlViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    var pdfDocument: PDFDocument?
    var isLandscape: Bool = false
    var isAnnotationMode: Bool = false
    var drawings: [Int: PKDrawing] = [:]
    var onPageChanged: ((Int) -> Void)?
    var onDrawingsChanged: (([Int: PKDrawing]) -> Void)?
    var currentPageIndex: Int = 0

    init(pdfDocument: PDFDocument, isLandscape: Bool) {
        self.pdfDocument = pdfDocument
        self.isLandscape = isLandscape

        let spineLocation: UIPageViewController.SpineLocation = isLandscape ? .mid : .max

        super.init(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [
                .spineLocation: NSNumber(value: spineLocation.rawValue),
                .interPageSpacing: 0
            ]
        )

        self.dataSource = self
        self.delegate = self
        self.view.semanticContentAttribute = .forceRightToLeft
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    func goToPage(_ pageIndex: Int, animated: Bool = false) {
        guard let pdfDocument = pdfDocument,
              pageIndex >= 0,
              pageIndex < pdfDocument.pageCount else { return }

        // Sauvegarder les dessins actuels avant de changer de page
        saveCurrentDrawings()

        currentPageIndex = pageIndex

        let viewControllers: [UIViewController]

        if isLandscape {
            // En mode paysage, spine .mid EXIGE toujours 2 view controllers
            if pageIndex == 0 {
                var controllers: [UIViewController] = []
                
                // Page vide à gauche
                let emptyVC = EmptyPageViewController()
                controllers.append(emptyVC)

                // Page 0 à droite
                if let page0 = pdfDocument.page(at: 0) {
                    let page0VC = createPageViewController(for: 0, page: page0)
                    controllers.append(page0VC)
                }

                viewControllers = controllers
            } else {
                // Paires : (1,2), (3,4), (5,6)...
                let pairStart = pageIndex % 2 == 1 ? pageIndex : pageIndex - 1
                var controllers: [UIViewController] = []

                let rightPageIndex = pairStart      // Impair (1, 3, 5...) → droite
                let leftPageIndex = pairStart + 1   // Pair (2, 4, 6...) → gauche

                // Array inversé pour RTL: [leftVC, rightVC]

                // PREMIER dans l'array: Page de GAUCHE (index pair)
                if leftPageIndex < pdfDocument.pageCount, let leftPage = pdfDocument.page(at: leftPageIndex) {
                    let leftVC = createPageViewController(for: leftPageIndex, page: leftPage)
                    controllers.append(leftVC)
                } else {
                    // Si pas de page gauche, ajouter une page vide pour respecter spine .mid
                    controllers.append(EmptyPageViewController())
                }

                // DEUXIÈME dans l'array: Page de DROITE (index impair)
                if let rightPage = pdfDocument.page(at: rightPageIndex) {
                    let rightVC = createPageViewController(for: rightPageIndex, page: rightPage)
                    controllers.append(rightVC)
                }

                viewControllers = controllers
            }
        } else {
            // En portrait : 1 page suffit (spine .max)
            viewControllers = createViewControllers(startingAt: pageIndex, count: 1)
        }

        guard !viewControllers.isEmpty else { return }
        
        // S'assurer qu'on a le bon nombre de VCs
        if isLandscape && viewControllers.count != 2 {
            print("⚠️ Erreur: Paysage nécessite 2 VCs, seulement \(viewControllers.count) fourni(s)")
            return
        }

        setViewControllers(viewControllers, direction: .forward, animated: animated)
    }

    private func createPageViewController(for pageIndex: Int, page: PDFPage) -> PDFPageWithAnnotationViewController {
        let pageVC = PDFPageWithAnnotationViewController(
            page: page,
            pageIndex: pageIndex,
            drawing: drawings[pageIndex] ?? PKDrawing(),
            isAnnotationMode: isAnnotationMode
        )
        
        pageVC.onDrawingChanged = { [weak self] pageIndex, drawing in
            self?.drawings[pageIndex] = drawing
            self?.onDrawingsChanged?(self?.drawings ?? [:])
        }
        
        return pageVC
    }

    private func createViewControllers(startingAt index: Int, count: Int) -> [UIViewController] {
        guard let pdfDocument = pdfDocument else { return [] }

        var controllers: [UIViewController] = []

        for i in 0..<count {
            let pageIndex = index + i
            guard pageIndex < pdfDocument.pageCount,
                  let page = pdfDocument.page(at: pageIndex) else { continue }

            let pageVC = createPageViewController(for: pageIndex, page: page)
            controllers.append(pageVC)
        }

        return controllers
    }

    func saveCurrentDrawings() {
        // Sauvegarder les dessins des pages actuellement visibles
        if let visibleVCs = viewControllers {
            for vc in visibleVCs {
                if let pageVC = vc as? PDFPageWithAnnotationViewController {
                    let drawing = pageVC.getCurrentDrawing()
                    drawings[pageVC.pageIndex] = drawing
                }
            }
            onDrawingsChanged?(drawings)
        }
    }

    // MARK: - UIPageViewControllerDataSource

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        if viewController is EmptyPageViewController {
            guard let pdfDocument = pdfDocument, pdfDocument.pageCount > 1 else { return nil }
            
            if isLandscape {
                // En mode paysage, retourner nil car la page vide est déjà dans la paire avec page 0
                return nil
            } else {
                // En portrait, aller à page 1
                guard let page1 = pdfDocument.page(at: 1) else { return nil }
                return createPageViewController(for: 1, page: page1)
            }
        }

        guard let pageVC = viewController as? PDFPageWithAnnotationViewController,
              let pdfDocument = pdfDocument else { return nil }

        if isLandscape {
            let currentIndex = pageVC.pageIndex

            if currentIndex == 0 {
                // Page 0 → aller à page 1 (avec page 2 si elle existe)
                guard pdfDocument.pageCount > 1 else { return nil }
                guard let page1 = pdfDocument.page(at: 1) else { return nil }
                return createPageViewController(for: 1, page: page1)
            } else if currentIndex % 2 == 1 {
                // Page IMPAIRE (droite) → retourner page PAIRE adjacente (gauche, même paire)
                let leftIndex = currentIndex + 1
                guard leftIndex < pdfDocument.pageCount,
                      let leftPage = pdfDocument.page(at: leftIndex) else { return nil }
                return createPageViewController(for: leftIndex, page: leftPage)
            } else {
                // Page PAIRE (gauche) → retourner page IMPAIRE suivante (droite, paire suivante)
                let nextRightIndex = currentIndex + 1
                guard nextRightIndex < pdfDocument.pageCount,
                      let nextRightPage = pdfDocument.page(at: nextRightIndex) else { return nil }
                return createPageViewController(for: nextRightIndex, page: nextRightPage)
            }
        } else {
            // En portrait : before = page suivante (RTL)
            let nextIndex = pageVC.pageIndex + 1
            guard nextIndex < pdfDocument.pageCount else { return nil }
            let controllers = createViewControllers(startingAt: nextIndex, count: 1)
            return controllers.first
        }
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        if viewController is EmptyPageViewController {
            // Page vide → pas de page avant (début du livre)
            return nil
        }

        guard let pageVC = viewController as? PDFPageWithAnnotationViewController,
              let pdfDocument = pdfDocument else { return nil }

        if isLandscape {
            let currentIndex = pageVC.pageIndex

            if currentIndex == 0 {
                // Page 0 → pas de page avant
                return nil
            } else if currentIndex == 1 {
                // Page 1 → retourner à page 0 (page vide sera gérée par goToPage)
                guard let page0 = pdfDocument.page(at: 0) else { return nil }
                return createPageViewController(for: 0, page: page0)
            } else if currentIndex % 2 == 0 {
                // Page PAIRE (gauche) → retourner page IMPAIRE adjacente (droite, même paire)
                let rightIndex = currentIndex - 1
                guard rightIndex >= 1,
                      let rightPage = pdfDocument.page(at: rightIndex) else { return nil }
                return createPageViewController(for: rightIndex, page: rightPage)
            } else {
                // Page IMPAIRE > 1 (droite) → retourner page PAIRE précédente (gauche, paire précédente)
                let prevLeftIndex = currentIndex - 1
                guard prevLeftIndex >= 1,
                      let prevLeftPage = pdfDocument.page(at: prevLeftIndex) else { return nil }
                return createPageViewController(for: prevLeftIndex, page: prevLeftPage)
            }
        } else {
            // En portrait : after = page précédente (RTL)
            let previousIndex = pageVC.pageIndex - 1
            guard previousIndex >= 0 else { return nil }
            let controllers = createViewControllers(startingAt: previousIndex, count: 1)
            return controllers.first
        }
    }

    // MARK: - UIPageViewControllerDelegate

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        // Sauvegarder avant la transition
        saveCurrentDrawings()
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed {
            // Sauvegarder les dessins des pages précédentes
            for vc in previousViewControllers {
                if let pageVC = vc as? PDFPageWithAnnotationViewController {
                    let drawing = pageVC.getCurrentDrawing()
                    drawings[pageVC.pageIndex] = drawing
                }
            }
            onDrawingsChanged?(drawings)

            if isLandscape {
                if let vcs = viewControllers {
                    for vc in vcs {
                        if vc is EmptyPageViewController {
                            currentPageIndex = 0
                            onPageChanged?(0)
                            break
                        }

                        if let pageVC = vc as? PDFPageWithAnnotationViewController {
                            if pageVC.pageIndex == 0 || pageVC.pageIndex % 2 == 1 {
                                currentPageIndex = pageVC.pageIndex
                                onPageChanged?(pageVC.pageIndex)
                                break
                            }
                        }
                    }
                }
            } else {
                if let visibleVC = viewControllers?.first as? PDFPageWithAnnotationViewController {
                    currentPageIndex = visibleVC.pageIndex
                    onPageChanged?(visibleVC.pageIndex)
                }
            }
        }
    }
}

// ViewController pour une page PDF avec canvas d'annotation
class PDFPageWithAnnotationViewController: UIViewController {

    let pageIndex: Int
    private let pdfView: PDFView
    private let canvasView: PassthroughCanvasView
    private var drawing: PKDrawing
    private var isAnnotationMode: Bool
    private var drawingObserver: NSObjectProtocol?

    var onDrawingChanged: ((Int, PKDrawing) -> Void)?

    init(page: PDFPage, pageIndex: Int, drawing: PKDrawing, isAnnotationMode: Bool) {
        self.pageIndex = pageIndex
        self.drawing = drawing
        self.isAnnotationMode = isAnnotationMode

        self.pdfView = PDFView()
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        pdfView.document = doc
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.backgroundColor = .systemBackground
        pdfView.pageShadowsEnabled = false

        self.canvasView = PassthroughCanvasView()
        canvasView.drawing = drawing
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.allowPassthrough = !isAnnotationMode

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        view.addSubview(pdfView)
        view.addSubview(canvasView)

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // Observer les changements de dessin pour sauvegarder automatiquement
        drawingObserver = NotificationCenter.default.addObserver(
            forName: .init("PKCanvasViewDrawingDidChange"),
            object: canvasView,
            queue: .main
        ) { [weak self] _ in
            self?.saveDrawing()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let window = view.window {
            let toolPicker = PKToolPicker.shared(for: window)
            toolPicker?.addObserver(canvasView)

            if isAnnotationMode {
                canvasView.becomeFirstResponder()
                toolPicker?.setVisible(true, forFirstResponder: canvasView)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveDrawing()
    }
    
    deinit {
        if let observer = drawingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func saveDrawing() {
        // Sauvegarder uniquement si le dessin a changé
        let currentDrawing = canvasView.drawing
        if currentDrawing.dataRepresentation() != drawing.dataRepresentation() {
            drawing = currentDrawing
            onDrawingChanged?(pageIndex, currentDrawing)
        }
    }

    func getCurrentDrawing() -> PKDrawing {
        return canvasView.drawing
    }

    func updateAnnotationMode(_ enabled: Bool) {
        isAnnotationMode = enabled
        canvasView.allowPassthrough = !enabled

        if let window = view.window, let toolPicker = PKToolPicker.shared(for: window) {
            if enabled {
                canvasView.becomeFirstResponder()
                toolPicker.setVisible(true, forFirstResponder: canvasView)
            } else {
                toolPicker.setVisible(false, forFirstResponder: canvasView)
                canvasView.resignFirstResponder()
            }
        }
    }
}

// SwiftUI Wrapper
struct QuranPageCurlView: UIViewControllerRepresentable {
    let pdfDocument: PDFDocument
    @Binding var currentPage: Int
    @Binding var isAnnotationMode: Bool
    @Binding var isLandscape: Bool
    @Binding var drawings: [Int: PKDrawing]

    func makeUIViewController(context: Context) -> QuranPageCurlViewController {
        let vc = QuranPageCurlViewController(pdfDocument: pdfDocument, isLandscape: isLandscape)

        vc.drawings = drawings
        vc.isAnnotationMode = isAnnotationMode

        vc.onPageChanged = { pageIndex in
            DispatchQueue.main.async {
                currentPage = pageIndex
            }
        }

        vc.onDrawingsChanged = { updatedDrawings in
            DispatchQueue.main.async {
                drawings = updatedDrawings
            }
        }

        vc.goToPage(currentPage, animated: false)

        return vc
    }

    func updateUIViewController(_ uiViewController: QuranPageCurlViewController, context: Context) {
        uiViewController.isAnnotationMode = isAnnotationMode

        // Sauvegarder les dessins actuels
        uiViewController.saveCurrentDrawings()

        if let visibleVCs = uiViewController.viewControllers {
            for vc in visibleVCs {
                if let pageVC = vc as? PDFPageWithAnnotationViewController {
                    pageVC.updateAnnotationMode(isAnnotationMode)
                }
            }
        }

        if uiViewController.currentPageIndex != currentPage {
            uiViewController.goToPage(currentPage, animated: false)
        }
    }

    static func dismantleUIViewController(_ uiViewController: QuranPageCurlViewController, coordinator: ()) {
        uiViewController.saveCurrentDrawings()
    }
}
