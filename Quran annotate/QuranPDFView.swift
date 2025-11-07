//
//  QuranPDFView.swift
//  Quran annotate
//
//  Created by Macbook Air on 06/11/2025.
//

import SwiftUI
import PDFKit
import PencilKit

// Gestionnaire de sauvegarde des annotations et de la dernière page
class DrawingsManager {
    static let shared = DrawingsManager()

    private let userDefaults = UserDefaults.standard
    private let drawingsKey = "quran_drawings"
    private let lastPageKey = "quran_last_pages"
    
    func saveDrawings(_ drawings: [Int: PKDrawing], for pdfName: String) {
        var allDrawings = loadAllDrawings()
        
        // Convertir les PKDrawing en Data
        var drawingsData: [String: Data] = [:]
        for (pageIndex, drawing) in drawings {
            if let data = try? drawing.dataRepresentation() {
                drawingsData[String(pageIndex)] = data
            }
        }
        
        allDrawings[pdfName] = drawingsData
        
        // Sauvegarder dans UserDefaults
        if let encoded = try? JSONEncoder().encode(allDrawings) {
            userDefaults.set(encoded, forKey: drawingsKey)
        }
    }
    
    func loadDrawings(for pdfName: String) -> [Int: PKDrawing] {
        let allDrawings = loadAllDrawings()
        
        guard let drawingsData = allDrawings[pdfName] else { return [:] }
        
        var drawings: [Int: PKDrawing] = [:]
        for (pageIndexString, data) in drawingsData {
            if let pageIndex = Int(pageIndexString),
               let drawing = try? PKDrawing(data: data) {
                drawings[pageIndex] = drawing
            }
        }
        
        return drawings
    }
    
    private func loadAllDrawings() -> [String: [String: Data]] {
        guard let data = userDefaults.data(forKey: drawingsKey),
              let decoded = try? JSONDecoder().decode([String: [String: Data]].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    func clearDrawings(for pdfName: String) {
        var allDrawings = loadAllDrawings()
        allDrawings.removeValue(forKey: pdfName)

        if let encoded = try? JSONEncoder().encode(allDrawings) {
            userDefaults.set(encoded, forKey: drawingsKey)
        }
    }

    // Sauvegarder la dernière page consultée
    func saveLastPage(_ page: Int, for pdfName: String) {
        var allLastPages = loadAllLastPages()
        allLastPages[pdfName] = page
        userDefaults.set(allLastPages, forKey: lastPageKey)
    }

    // Charger la dernière page consultée
    func loadLastPage(for pdfName: String) -> Int? {
        let allLastPages = loadAllLastPages()
        return allLastPages[pdfName]
    }

    private func loadAllLastPages() -> [String: Int] {
        return userDefaults.dictionary(forKey: lastPageKey) as? [String: Int] ?? [:]
    }
}

// Vue principale du Coran avec contrôles
struct QuranPDFView: View {
    @StateObject private var viewModel = QuranPDFViewModel()
    @State private var isAnnotationMode = false
    @State private var showPageSelector = false
    @State private var drawings: [Int: PKDrawing] = [:]
    @State private var selectedPDF: String? = nil
    @State private var showSplashScreen = true
    @State private var orientationKey = UUID()
    @State private var coordinatorRef: QuranPageCurlView.Coordinator? = nil
    @Environment(\.scenePhase) private var scenePhase // Pour détecter quand l'app va en arrière-plan

    var body: some View {
        ZStack {
            // Splash screen initial
            if showSplashScreen {
                SplashScreenView(isLoading: $showSplashScreen)
                    .transition(.opacity)
            }
            // Écran de sélection du PDF
            else if selectedPDF == nil {
                PDFSelectionView(selectedPDF: $selectedPDF)
                    .transition(.opacity)
            }
            // Vue de chargement
            else if viewModel.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("تحميل القرآن الكريم...")
                        .font(.headline)
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
            // Vue PDF avec annotations et page curl natif
            else if let document = viewModel.pdfDocument {
                QuranPageCurlView(
                    pdfDocument: document,
                    currentPage: $viewModel.currentPage,
                    isAnnotationMode: $isAnnotationMode,
                    isLandscape: $viewModel.isLandscape,
                    drawings: $drawings,
                    coordinatorRef: $coordinatorRef
                )
                .id(orientationKey) // Forcer recréation quand l'orientation change
                .edgesIgnoringSafeArea(.all)
            }

            // Overlay des contrôles (seulement si PDF chargé)
            if viewModel.pdfDocument != nil {
                VStack(spacing: 0) {
                    // Barre supérieure
                    HStack {
                        // Bouton retour (à gauche en RTL)
                        Button(action: {
                            // 1. Sauvegarder les dessins visibles via le coordinator
                            coordinatorRef?.saveCurrentDrawings()

                            // 2. Sauvegarder dans UserDefaults (annotations + page actuelle)
                            if let pdfName = selectedPDF {
                                DrawingsManager.shared.saveDrawings(drawings, for: pdfName)
                                DrawingsManager.shared.saveLastPage(viewModel.currentPage, for: pdfName)
                            }

                            // 3. Nettoyer le PKToolPicker
                            if let coordinator = coordinatorRef,
                               let vc = coordinator.viewController,
                               let visibleVCs = vc.viewControllers {
                                for visibleVC in visibleVCs {
                                    if let pageVC = visibleVC as? PDFPageWithAnnotationViewController {
                                        ToolPickerManager.shared.hideToolPicker(for: pageVC.canvasView)
                                    }
                                }
                            }

                            // 4. Retourner à l'écran de sélection
                            selectedPDF = nil
                        }) {
                            Image(systemName: "chevron.left.circle")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .padding()
                                .background(Color(.systemBackground).opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }

                        // Bouton pour effacer les annotations des pages visibles
                        Button(action: {
                            // Obtenir les pages visibles via le coordinator
                            if let coordinator = coordinatorRef,
                               let vc = coordinator.viewController,
                               let visibleVCs = vc.viewControllers {

                                // Supprimer les annotations des pages visibles
                                for visibleVC in visibleVCs {
                                    if let pageVC = visibleVC as? PDFPageWithAnnotationViewController {
                                        // Supprimer du dictionnaire
                                        drawings.removeValue(forKey: pageVC.pageIndex)
                                        // Effacer le canvas
                                        pageVC.clearDrawing()
                                    }
                                }

                                // Sauvegarder
                                if let pdfName = selectedPDF {
                                    DrawingsManager.shared.saveDrawings(drawings, for: pdfName)
                                }
                            }
                        }) {
                            Image(systemName: "trash.circle")
                                .font(.title2)
                                .foregroundColor(.red)
                                .padding()
                                .background(Color(.systemBackground).opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }

                        Spacer()

                        // Bouton mode annotation (à droite en RTL)
                        Button(action: {
                            withAnimation {
                                isAnnotationMode.toggle()
                            }
                        }) {
                            Image(systemName: isAnnotationMode ? "pencil.circle.fill" : "pencil.circle")
                                .font(.title2)
                                .foregroundColor(isAnnotationMode ? .blue : .primary)
                                .padding()
                                .background(Color(.systemBackground).opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                    }
                    .padding()

                    Spacer()

                    // Barre de progression en bas (discrète)
                    RTLProgressBar(
                        currentPage: $viewModel.currentPage,
                        totalPages: viewModel.totalPages
                    )
                    .padding(.bottom, 60)
                }
            }
        }
        .onChange(of: selectedPDF) { oldValue, newValue in
            if let pdfName = newValue {
                // Charger le PDF
                viewModel.loadPDF(named: pdfName)
                // Charger les annotations sauvegardées
                drawings = DrawingsManager.shared.loadDrawings(for: pdfName)
                // Restaurer la dernière page consultée (avec un délai pour éviter le crash)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let lastPage = DrawingsManager.shared.loadLastPage(for: pdfName) {
                        viewModel.currentPage = lastPage
                    }
                }
            } else {
                // Retour à l'écran de sélection

                // 1. Sauvegarder la dernière page avant de quitter
                if let oldPdfName = oldValue {
                    DrawingsManager.shared.saveLastPage(viewModel.currentPage, for: oldPdfName)
                }

                // 2. Désactiver le mode annotation
                isAnnotationMode = false

                // 3. Nettoyer le PDF du viewModel
                viewModel.pdfDocument = nil
                viewModel.currentPage = 0
                viewModel.totalPages = 0

                // 4. Réinitialiser l'orientationKey pour forcer une nouvelle création
                orientationKey = UUID()

                // 5. Réinitialiser le coordinatorRef pour le prochain livre
                coordinatorRef = nil

                // 6. NE PAS vider drawings ici - ils seront écrasés lors du prochain loadDrawings()
                // Cela évite de déclencher un onChange(of: drawings) qui pourrait causer des problèmes

                // 7. Réinitialiser le flag d'outil par défaut pour le prochain livre
                ToolPickerManager.shared.resetDefaultToolFlag()
            }
        }
        .onChange(of: drawings) { oldValue, newValue in
            // Sauvegarder automatiquement les annotations
            // IMPORTANT : Ne sauvegarder que si on a un PDF sélectionné
            if let pdfName = selectedPDF {
                DrawingsManager.shared.saveDrawings(newValue, for: pdfName)
            }
        }
        .onChange(of: viewModel.currentPage) { oldValue, newValue in
            // Sauvegarder automatiquement la page courante
            if let pdfName = selectedPDF {
                DrawingsManager.shared.saveLastPage(newValue, for: pdfName)
            }
        }
        .onChange(of: viewModel.isLandscape) { oldValue, newValue in
            // Sauvegarder les dessins visibles AVANT la rotation via le coordinator
            coordinatorRef?.saveCurrentDrawings()

            // Sauvegarder dans UserDefaults
            if let pdfName = selectedPDF {
                DrawingsManager.shared.saveDrawings(drawings, for: pdfName)
            }

            // Changer la clé pour forcer la recréation du view controller
            orientationKey = UUID()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                // App passe en arrière-plan : sauvegarder l'état de l'outil
                if let coordinator = coordinatorRef,
                   let vc = coordinator.viewController {
                    ToolPickerManager.shared.saveToolState(vc.currentTool)
                }

                // Sauvegarder les dessins aussi
                if let pdfName = selectedPDF {
                    DrawingsManager.shared.saveDrawings(drawings, for: pdfName)
                }

            case .active:
                // App revient en foreground : restaurer l'outil si disponible
                if let coordinator = coordinatorRef,
                   let vc = coordinator.viewController,
                   let visibleVCs = vc.viewControllers {

                    // Restaurer l'outil sauvegardé sur toutes les pages visibles
                    for visibleVC in visibleVCs {
                        if let pageVC = visibleVC as? PDFPageWithAnnotationViewController {
                            ToolPickerManager.shared.restoreToolIfNeeded(for: pageVC.canvasView)
                        }
                    }
                }

            case .inactive:
                // État transitoire, ne rien faire
                break

            @unknown default:
                break
            }
        }
        .sheet(isPresented: $showPageSelector) {
            PageSelectorView(
                currentPage: $viewModel.currentPage,
                totalPages: viewModel.totalPages,
                isPresented: $showPageSelector
            )
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onDisappear {
            // Sauvegarder quand l'app se ferme
            if let pdfName = selectedPDF {
                DrawingsManager.shared.saveDrawings(drawings, for: pdfName)
                DrawingsManager.shared.saveLastPage(viewModel.currentPage, for: pdfName)
            }
        }
    }
}

// Barre de progression RTL personnalisée (discrète mais visible)
struct RTLProgressBar: View {
    @Binding var currentPage: Int
    let totalPages: Int

    @State private var dragOffset: Int? = nil

    var body: some View {
        GeometryReader { geometry in
            // ZStack pour barre de fond + progression
            ZStack(alignment: .trailing) { // Alignement à droite pour RTL
                // Fond (subtil mais visible)
                Capsule()
                    .fill(Color(.systemGray5).opacity(0.6))
                    .frame(height: 5)

                // Progression (pages restantes - se vide de droite à gauche)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.5),
                                Color.accentColor.opacity(0.35)
                            ],
                            startPoint: .trailing,
                            endPoint: .leading
                        )
                    )
                    .frame(
                        width: max(5, geometry.size.width * CGFloat(totalPages - (dragOffset ?? currentPage)) / CGFloat(totalPages)),
                        height: 5
                    )
                    .animation(.easeInOut(duration: 0.15), value: dragOffset ?? currentPage)
            }
            // Zone de toucher plus grande pour faciliter l'interaction
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Calcul du pourcentage drag RTL (droite = début, gauche = fin)
                        let relative = 1 - (value.location.x / geometry.size.width)
                        let clampedRelative = min(max(relative, 0), 1)
                        let page = min(max(Int(clampedRelative * CGFloat(totalPages)), 0), totalPages - 1)
                        dragOffset = page
                    }
                    .onEnded { _ in
                        if let page = dragOffset {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentPage = page
                            }
                        }
                        dragOffset = nil
                    }
            )
        }
        .frame(height: 24)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(
            Color.clear
        )
    }
}

// Sélecteur de page
struct PageSelectorView: View {
    @Binding var currentPage: Int
    let totalPages: Int
    @Binding var isPresented: Bool
    @State private var selectedPage: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("الذهاب إلى صفحة")
                    .font(.title2)
                    .bold()

                TextField("رقم الصفحة", text: $selectedPage)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .padding(.horizontal, 40)

                Text("من 1 إلى \(totalPages)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("انتقال") {
                    if let pageNumber = Int(selectedPage),
                       pageNumber >= 1 && pageNumber <= totalPages {
                        currentPage = pageNumber - 1
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPage.isEmpty)
            }
            .padding()
            .navigationBarItems(trailing: Button("إلغاء") {
                isPresented = false
            })
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

#Preview {
    QuranPDFView()
}
