//
//  QuranPDFViewModel.swift
//  Quran annotate
//
//  Created by Macbook Air on 06/11/2025.
//

import Foundation
import PDFKit
import SwiftUI
import Combine

class QuranPDFViewModel: ObservableObject {
    @Published var pdfDocument: PDFDocument?
    @Published var currentPage: Int = 0
    @Published var totalPages: Int = 0
    @Published var isLandscape: Bool = false
    @Published var isLoading: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupOrientationObserver()
    }

    private func setupOrientationObserver() {
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateOrientation()
            }
            .store(in: &cancellables)

        // Mise à jour initiale
        updateOrientation()
    }

    private func updateOrientation() {
        let orientation = UIDevice.current.orientation
        DispatchQueue.main.async {
            self.isLandscape = orientation.isLandscape
        }
    }

    func loadPDF(named pdfName: String) {
        print("🔍 Tentative de chargement du PDF: \(pdfName)")
        isLoading = true

        // Charger en background pour ne pas bloquer l'UI
        DispatchQueue.global(qos: .userInitiated).async {
            // Lister tous les PDFs dans le bundle pour débugger
            if let bundlePath = Bundle.main.resourcePath {
                print("📂 Bundle path: \(bundlePath)")
                do {
                    let items = try FileManager.default.contentsOfDirectory(atPath: bundlePath)
                    let pdfs = items.filter { $0.hasSuffix(".pdf") }
                    print("📄 PDFs trouvés dans le bundle: \(pdfs)")
                } catch {
                    print("❌ Erreur lors de la lecture du bundle: \(error)")
                }
            }

            guard let url = Bundle.main.url(forResource: pdfName, withExtension: "pdf") else {
                print("❌ Erreur: Impossible de trouver le fichier PDF: \(pdfName).pdf")
                print("🔍 Recherche dans le bundle...")
                // Essayer de trouver le fichier avec n'importe quelle extension
                if let allURLs = Bundle.main.urls(forResourcesWithExtension: "pdf", subdirectory: nil) {
                    print("📚 Tous les PDFs dans le bundle:")
                    for pdfURL in allURLs {
                        print("  - \(pdfURL.lastPathComponent)")
                    }
                }
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }

            print("✅ PDF trouvé à l'URL: \(url)")

            guard let document = PDFDocument(url: url) else {
                print("❌ Erreur: Impossible de charger le PDF depuis l'URL: \(url)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }

            print("📖 Document PDF créé avec \(document.pageCount) pages")

            DispatchQueue.main.async {
                self.pdfDocument = document
                self.totalPages = document.pageCount
                // NE PAS réinitialiser currentPage à 0 - garder la valeur existante pour la restauration
                self.isLoading = false
                print("✅ PDF chargé avec succès: \(self.totalPages) pages, page actuelle: \(self.currentPage)")
            }
        }
    }

    func goToPage(_ pageNumber: Int) {
        guard pageNumber >= 0 && pageNumber < totalPages else { return }
        currentPage = pageNumber
    }

    func nextPage() {
        // Navigation RTL: suivant = page précédente (vers la gauche)
        if currentPage > 0 {
            currentPage -= 1
        }
    }

    func previousPage() {
        // Navigation RTL: précédent = page suivante (vers la droite)
        if currentPage < totalPages - 1 {
            currentPage += 1
        }
    }
}
