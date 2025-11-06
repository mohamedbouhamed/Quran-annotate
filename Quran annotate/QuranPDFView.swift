//
//  QuranPDFView.swift
//  Quran annotate
//
//  Created by Macbook Air on 06/11/2025.
//

import SwiftUI
import PDFKit
import PencilKit

// Gestionnaire de sauvegarde des annotations
class DrawingsManager {
    static let shared = DrawingsManager()
    
    private let userDefaults = UserDefaults.standard
    private let drawingsKey = "quran_drawings"
    
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
                    drawings: $drawings
                )
                .id(orientationKey) // Forcer recréation quand l'orientation change
                .edgesIgnoringSafeArea(.all)
            }

            // Overlay des contrôles (seulement si PDF chargé)
            if viewModel.pdfDocument != nil {
                VStack {
                    // Barre supérieure
                    HStack {
                        // Bouton pour effacer toutes les annotations (à gauche en RTL)
                        Button(action: {
                            drawings = [:]
                            if let pdfName = selectedPDF {
                                DrawingsManager.shared.clearDrawings(for: pdfName)
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
                }
            }
        }
        .onChange(of: selectedPDF) { oldValue, newValue in
            if let pdfName = newValue {
                // Charger le PDF
                viewModel.loadPDF(named: pdfName)
                // Charger les annotations sauvegardées
                drawings = DrawingsManager.shared.loadDrawings(for: pdfName)
            }
        }
        .onChange(of: drawings) { oldValue, newValue in
            // Sauvegarder automatiquement les annotations
            if let pdfName = selectedPDF {
                DrawingsManager.shared.saveDrawings(newValue, for: pdfName)
            }
        }
        .onChange(of: viewModel.isLandscape) { oldValue, newValue in
            // Sauvegarder avant de changer d'orientation
            if let pdfName = selectedPDF {
                DrawingsManager.shared.saveDrawings(drawings, for: pdfName)
            }
            // Changer la clé pour forcer la recréation du view controller
            orientationKey = UUID()
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
            }
        }
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
