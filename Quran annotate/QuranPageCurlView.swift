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

// Singleton pour gérer le PKToolPicker
class ToolPickerManager {
    static let shared = ToolPickerManager()
    private(set) var toolPicker: PKToolPicker

    private init() {
        // Créer une instance unique de PKToolPicker
        toolPicker = PKToolPicker()
    }

    func setupToolPicker(for canvasView: PKCanvasView, in window: UIWindow) {
        toolPicker.addObserver(canvasView)
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        canvasView.becomeFirstResponder()
    }

    func hideToolPicker(for canvasView: PKCanvasView) {
        toolPicker.setVisible(false, forFirstResponder: canvasView)
        canvasView.resignFirstResponder()
    }
}

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
    var currentTool: PKTool?

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
            // Paires : (0,1), (2,3), (4,5)...
            let pairStart = pageIndex % 2 == 0 ? pageIndex : pageIndex - 1
            var controllers: [UIViewController] = []

            let rightPageIndex = pairStart      // Pair (0, 2, 4...) → droite
            let leftPageIndex = pairStart + 1   // Impair (1, 3, 5...) → gauche

            // Array inversé pour RTL: [leftVC, rightVC]

            // PREMIER dans l'array: Page de GAUCHE (index impair)
            if leftPageIndex < pdfDocument.pageCount, let leftPage = pdfDocument.page(at: leftPageIndex) {
                let leftVC = createPageViewController(for: leftPageIndex, page: leftPage)
                controllers.append(leftVC)
            } else {
                // Si pas de page gauche, ajouter une page vide pour respecter spine .mid
                controllers.append(EmptyPageViewController())
            }

            // DEUXIÈME dans l'array: Page de DROITE (index pair)
            if let rightPage = pdfDocument.page(at: rightPageIndex) {
                let rightVC = createPageViewController(for: rightPageIndex, page: rightPage)
                controllers.append(rightVC)
            }

            viewControllers = controllers
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

        // Appliquer l'outil actuel si disponible
        if let tool = currentTool {
            pageVC.setTool(tool)
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

    func updateAnnotationModeForAllPages() {
        // Mettre à jour le mode annotation sur toutes les pages visibles
        if let visibleVCs = viewControllers {
            for vc in visibleVCs {
                if let pageVC = vc as? PDFPageWithAnnotationViewController {
                    pageVC.updateAnnotationMode(isAnnotationMode)
                }
            }
        }
    }

    func clearVisibleAnnotations() {
        // Effacer les annotations sur toutes les pages visibles
        if let visibleVCs = viewControllers {
            for vc in visibleVCs {
                if let pageVC = vc as? PDFPageWithAnnotationViewController {
                    pageVC.clearDrawing()
                }
            }
        }
    }

    func restoreTool(_ tool: PKTool) {
        // Sauvegarder l'outil actuel
        currentTool = tool

        // Restaurer l'outil sur toutes les pages visibles
        if let visibleVCs = viewControllers {
            for vc in visibleVCs {
                if let pageVC = vc as? PDFPageWithAnnotationViewController {
                    pageVC.setTool(tool)
                }
            }
        }
    }

    // MARK: - UIPageViewControllerDataSource

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        if viewController is EmptyPageViewController {
            // Page vide à la fin → pas de page après
            return nil
        }

        guard let pageVC = viewController as? PDFPageWithAnnotationViewController,
              let pdfDocument = pdfDocument else { return nil }

        if isLandscape {
            let currentIndex = pageVC.pageIndex

            if currentIndex % 2 == 0 {
                // Page PAIRE (droite) → retourner page IMPAIRE adjacente (gauche, même paire)
                let leftIndex = currentIndex + 1
                guard leftIndex < pdfDocument.pageCount,
                      let leftPage = pdfDocument.page(at: leftIndex) else { return nil }
                return createPageViewController(for: leftIndex, page: leftPage)
            } else {
                // Page IMPAIRE (gauche) → retourner page PAIRE suivante (droite, paire suivante)
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
            // Page vide → pas de page avant
            return nil
        }

        guard let pageVC = viewController as? PDFPageWithAnnotationViewController,
              let pdfDocument = pdfDocument else { return nil }

        if isLandscape {
            let currentIndex = pageVC.pageIndex

            if currentIndex == 0 {
                // Page 0 → pas de page avant (début du livre)
                return nil
            } else if currentIndex % 2 == 1 {
                // Page IMPAIRE (gauche) → retourner page PAIRE adjacente (droite, même paire)
                let rightIndex = currentIndex - 1
                guard rightIndex >= 0,
                      let rightPage = pdfDocument.page(at: rightIndex) else { return nil }
                return createPageViewController(for: rightIndex, page: rightPage)
            } else {
                // Page PAIRE (droite) → retourner page IMPAIRE précédente (gauche, paire précédente)
                let prevLeftIndex = currentIndex - 1
                guard prevLeftIndex >= 0,
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
                // En mode paysage, retourner la page de DROITE (page paire) comme page courante
                if let vcs = viewControllers {
                    for vc in vcs {
                        if let pageVC = vc as? PDFPageWithAnnotationViewController {
                            if pageVC.pageIndex % 2 == 0 {
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
            // Utiliser le singleton ToolPickerManager
            if isAnnotationMode {
                ToolPickerManager.shared.setupToolPicker(for: canvasView, in: window)
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

    func getCurrentTool() -> PKTool? {
        return canvasView.tool
    }

    func setTool(_ tool: PKTool) {
        canvasView.tool = tool
    }

    func updateAnnotationMode(_ enabled: Bool) {
        isAnnotationMode = enabled
        canvasView.allowPassthrough = !enabled

        if let window = view.window {
            if enabled {
                ToolPickerManager.shared.setupToolPicker(for: canvasView, in: window)
            } else {
                ToolPickerManager.shared.hideToolPicker(for: canvasView)
            }
        }
    }

    func clearDrawing() {
        // Effacer le dessin sur le canvas
        canvasView.drawing = PKDrawing()
        drawing = PKDrawing()
        onDrawingChanged?(pageIndex, PKDrawing())
    }
}

// SwiftUI Wrapper
struct QuranPageCurlView: UIViewControllerRepresentable {
    let pdfDocument: PDFDocument
    @Binding var currentPage: Int
    @Binding var isAnnotationMode: Bool
    @Binding var isLandscape: Bool
    @Binding var drawings: [Int: PKDrawing]
    @Binding var coordinatorRef: QuranPageCurlView.Coordinator?

    class Coordinator: ObservableObject {
        var viewController: QuranPageCurlViewController?
        var drawings: Binding<[Int: PKDrawing]>?
        var savedTool: PKTool?
        var savedIsAnnotationMode: Bool = false

        func saveCurrentDrawings() {
            if let vc = viewController, let visibleVCs = vc.viewControllers {
                // Sauvegarder l'outil actuel
                for visibleVC in visibleVCs {
                    if let pageVC = visibleVC as? PDFPageWithAnnotationViewController {
                        // Sauvegarder les dessins
                        let drawing = pageVC.getCurrentDrawing()
                        vc.drawings[pageVC.pageIndex] = drawing

                        // Sauvegarder l'outil et le mode annotation
                        savedTool = pageVC.getCurrentTool()
                        savedIsAnnotationMode = vc.isAnnotationMode
                    }
                }
                // Mettre à jour le binding de manière synchrone
                drawings?.wrappedValue = vc.drawings
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        // Exposer le coordinator au parent via le binding
        DispatchQueue.main.async {
            coordinatorRef = coordinator
        }
        return coordinator
    }

    func makeUIViewController(context: Context) -> QuranPageCurlViewController {
        let vc = QuranPageCurlViewController(pdfDocument: pdfDocument, isLandscape: isLandscape)

        // Stocker la référence dans le coordinator
        context.coordinator.viewController = vc
        context.coordinator.drawings = $drawings

        // S'assurer que le coordinator est exposé
        if coordinatorRef == nil {
            DispatchQueue.main.async {
                coordinatorRef = context.coordinator
            }
        }


        vc.drawings = drawings
        vc.isAnnotationMode = isAnnotationMode

        vc.onPageChanged = { pageIndex in
            DispatchQueue.main.async {
                currentPage = pageIndex
            }
        }

        vc.onDrawingsChanged = { updatedDrawings in
            // Toujours mettre à jour de manière synchrone pour éviter les désynchronisations
            drawings = updatedDrawings
        }

        vc.goToPage(currentPage, animated: false)

        // Assurer que le mode annotation est correctement appliqué après la création
        DispatchQueue.main.async {
            // Restaurer le mode annotation sauvegardé si disponible
            if context.coordinator.savedIsAnnotationMode {
                vc.isAnnotationMode = context.coordinator.savedIsAnnotationMode
            }

            vc.updateAnnotationModeForAllPages()

            // Restaurer l'outil sauvegardé après rotation
            if let savedTool = context.coordinator.savedTool {
                vc.restoreTool(savedTool)
            }
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: QuranPageCurlViewController, context: Context) {
        // Mettre à jour la référence du coordinator
        context.coordinator.viewController = uiViewController

        // Vérifier si l'orientation a changé
        let orientationChanged = uiViewController.isLandscape != isLandscape

        // Si l'orientation a changé, ne rien faire car .id() va recréer le VC
        if orientationChanged {
            return
        }

        // Détecter si toutes les annotations ont été supprimées
        if drawings.isEmpty && !uiViewController.drawings.isEmpty {
            uiViewController.drawings = [:]
            uiViewController.clearVisibleAnnotations()
        } else {
            uiViewController.drawings = drawings
        }

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
