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

// UIPageViewController avec page curl pour le Coran
class QuranPageCurlViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    var pdfDocument: PDFDocument?
    var isLandscape: Bool = false
    var isAnnotationMode: Bool = false
    var drawings: [Int: PKDrawing] = [:]
    var onPageChanged: ((Int) -> Void)?
    var currentPageIndex: Int = 0

    init(pdfDocument: PDFDocument, isLandscape: Bool) {
        self.pdfDocument = pdfDocument
        self.isLandscape = isLandscape

        // Configuration du spine selon l'orientation
        // En paysage: .mid (spine au milieu, livre ouvert)
        // En portrait: .max (spine à droite pour l'arabe, curl depuis la gauche)
        let spineLocation: UIPageViewController.SpineLocation = isLandscape ? .mid : .max

        // IMPORTANT: transitionStyle = .pageCurl pour l'animation de livre réaliste
        super.init(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [
                .spineLocation: NSNumber(value: spineLocation.rawValue)
            ]
        )

        self.dataSource = self
        self.delegate = self

        // Configuration RTL pour que le curl parte de la droite
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

        currentPageIndex = pageIndex

        let viewControllers: [UIViewController]

        if isLandscape {
            // En paysage : 2 pages côte à côte (comme un livre arabe ouvert)
            // Ajuster pour être sur une page paire (début de paire)
            let adjustedIndex = (pageIndex / 2) * 2  // Arrondir à 0, 2, 4, 6...

            // Créer 2 view controllers
            // IMPORTANT: Avec semanticContentAttribute = .forceRightToLeft:
            // UIKit INVERSE l'ordre de l'array pour l'affichage RTL
            // Pour avoir: [page droite | page gauche] à l'écran
            // Il faut fournir: [page gauche, page droite] dans l'array
            // Donc ordre = [page impaire (gauche), page paire (droite)]
            var controllers: [UIViewController] = []

            let rightPageIndex = adjustedIndex      // Page paire (0, 2, 4...) → droite
            let leftPageIndex = adjustedIndex + 1   // Page impaire (1, 3, 5...) → gauche

            // PREMIER dans l'array: Page de GAUCHE (index impair)
            // Sera affichée à gauche après inversion RTL
            if leftPageIndex < pdfDocument.pageCount, let leftPage = pdfDocument.page(at: leftPageIndex) {
                let leftVC = PDFPageWithAnnotationViewController(
                    page: leftPage,
                    pageIndex: leftPageIndex,
                    drawing: drawings[leftPageIndex] ?? PKDrawing(),
                    isAnnotationMode: isAnnotationMode
                )
                leftVC.onDrawingChanged = { [weak self] drawing in
                    self?.drawings[leftPageIndex] = drawing
                }
                controllers.append(leftVC)
            }

            // DEUXIÈME dans l'array: Page de DROITE (index pair)
            // Sera affichée à droite après inversion RTL
            if let rightPage = pdfDocument.page(at: rightPageIndex) {
                let rightVC = PDFPageWithAnnotationViewController(
                    page: rightPage,
                    pageIndex: rightPageIndex,
                    drawing: drawings[rightPageIndex] ?? PKDrawing(),
                    isAnnotationMode: isAnnotationMode
                )
                rightVC.onDrawingChanged = { [weak self] drawing in
                    self?.drawings[rightPageIndex] = drawing
                }
                controllers.append(rightVC)
            }

            viewControllers = controllers
        } else {
            // En portrait : 1 page
            viewControllers = createViewControllers(startingAt: pageIndex, count: 1)
        }

        guard !viewControllers.isEmpty else { return }

        setViewControllers(viewControllers, direction: .forward, animated: animated)
    }

    private func createViewControllers(startingAt index: Int, count: Int) -> [UIViewController] {
        guard let pdfDocument = pdfDocument else { return [] }

        var controllers: [UIViewController] = []

        for i in 0..<count {
            let pageIndex = index + i
            guard pageIndex < pdfDocument.pageCount,
                  let page = pdfDocument.page(at: pageIndex) else { continue }

            let pageVC = PDFPageWithAnnotationViewController(
                page: page,
                pageIndex: pageIndex,
                drawing: drawings[pageIndex] ?? PKDrawing(),
                isAnnotationMode: isAnnotationMode
            )

            pageVC.onDrawingChanged = { [weak self] drawing in
                self?.drawings[pageIndex] = drawing
            }

            controllers.append(pageVC)
        }

        return controllers
    }

    func updateOrientation(_ newIsLandscape: Bool) {
        guard self.isLandscape != newIsLandscape else { return }

        // Sauvegarder la page actuelle
        let savedPage = currentPageIndex

        // Mettre à jour l'orientation
        self.isLandscape = newIsLandscape

        // Note: UIPageViewController ne permet pas de changer spineLocation après init
        // On doit recréer complètement le controller
        // Pour l'instant, on réaffiche juste la page avec le bon mode

        // Petite pause pour éviter les conflits
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.goToPage(savedPage, animated: false)
        }
    }

    // MARK: - UIPageViewControllerDataSource

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let pageVC = viewController as? PDFPageWithAnnotationViewController,
              let pdfDocument = pdfDocument else { return nil }

        if isLandscape {
            // En mode paysage avec 2 pages et spine au milieu
            // UIPageViewController nous passe l'un des 2 VCs de la paire actuelle
            // On doit identifier le début de la paire actuelle
            let currentPairStart = (pageVC.pageIndex / 2) * 2  // Arrondir à la paire (0,2,4,6...)

            // Pour RTL: before = pages suivantes (avancer)
            let nextPairStart = currentPairStart + 2

            guard nextPairStart < pdfDocument.pageCount else { return nil }

            // Retourner juste le premier VC de la paire (UIPageViewController demandera le 2ème automatiquement)
            let controllers = createViewControllers(startingAt: nextPairStart, count: 1)
            return controllers.first
        } else {
            // En portrait : une page à la fois
            // Pour RTL: before = page suivante (avancer)
            let nextIndex = pageVC.pageIndex + 1
            guard nextIndex < pdfDocument.pageCount else { return nil }

            let controllers = createViewControllers(startingAt: nextIndex, count: 1)
            return controllers.first
        }
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let pageVC = viewController as? PDFPageWithAnnotationViewController,
              let pdfDocument = pdfDocument else { return nil }

        if isLandscape {
            // En mode paysage avec 2 pages et spine au milieu
            let currentPairStart = (pageVC.pageIndex / 2) * 2  // Arrondir à la paire (0,2,4,6...)

            // Pour RTL: after = pages précédentes (reculer)
            let previousPairStart = currentPairStart - 2

            guard previousPairStart >= 0 else { return nil }

            // Retourner juste le premier VC de la paire
            let controllers = createViewControllers(startingAt: previousPairStart, count: 1)
            return controllers.first
        } else {
            // En portrait : une page à la fois
            // Pour RTL: after = page précédente (reculer)
            let previousIndex = pageVC.pageIndex - 1
            guard previousIndex >= 0 else { return nil }

            let controllers = createViewControllers(startingAt: previousIndex, count: 1)
            return controllers.first
        }
    }

    // MARK: - UIPageViewControllerDelegate

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed {
            // En mode paysage, on a 2 VCs. On veut toujours reporter l'index de la première page (paire)
            if isLandscape {
                // Avec l'ordre inversé [leftVC, rightVC], on doit chercher le VC avec l'index pair
                if let vcs = viewControllers {
                    for vc in vcs {
                        if let pageVC = vc as? PDFPageWithAnnotationViewController {
                            // Trouver l'index pair (0, 2, 4, 6...)
                            if pageVC.pageIndex % 2 == 0 {
                                currentPageIndex = pageVC.pageIndex
                                onPageChanged?(pageVC.pageIndex)
                                break
                            }
                        }
                    }
                }
            } else {
                // En portrait, simple
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

    var onDrawingChanged: ((PKDrawing) -> Void)?

    init(page: PDFPage, pageIndex: Int, drawing: PKDrawing, isAnnotationMode: Bool) {
        self.pageIndex = pageIndex
        self.drawing = drawing
        self.isAnnotationMode = isAnnotationMode

        // PDF View
        self.pdfView = PDFView()
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        pdfView.document = doc
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.backgroundColor = .systemBackground

        // Canvas View
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

        // Ajouter les vues
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

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Configuration du PKToolPicker natif
        if let window = view.window {
            let toolPicker = PKToolPicker.shared(for: window)
            toolPicker?.addObserver(canvasView)

            // Afficher le toolPicker si en mode annotation
            if isAnnotationMode {
                canvasView.becomeFirstResponder()
                toolPicker?.setVisible(true, forFirstResponder: canvasView)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Sauvegarder le dessin quand la page disparaît
        if !canvasView.drawing.bounds.isEmpty {
            onDrawingChanged?(canvasView.drawing)
        }
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

        // Restaurer les dessins existants
        vc.drawings = drawings
        vc.isAnnotationMode = isAnnotationMode

        vc.onPageChanged = { pageIndex in
            DispatchQueue.main.async {
                currentPage = pageIndex
            }
        }

        vc.goToPage(currentPage, animated: false)

        return vc
    }

    func updateUIViewController(_ uiViewController: QuranPageCurlViewController, context: Context) {
        uiViewController.isAnnotationMode = isAnnotationMode

        // Synchroniser les dessins du VC vers le binding (pour sauvegarder)
        drawings = uiViewController.drawings

        // Mettre à jour le mode annotation sur les pages visibles
        if let visibleVCs = uiViewController.viewControllers {
            for vc in visibleVCs {
                if let pageVC = vc as? PDFPageWithAnnotationViewController {
                    pageVC.updateAnnotationMode(isAnnotationMode)
                }
            }
        }

        // Mettre à jour la page si changée
        if uiViewController.currentPageIndex != currentPage {
            uiViewController.goToPage(currentPage, animated: false)
        }
    }

    static func dismantleUIViewController(_ uiViewController: QuranPageCurlViewController, coordinator: ()) {
        // Le binding drawings est déjà synchronisé via onPageChanged
    }
}
