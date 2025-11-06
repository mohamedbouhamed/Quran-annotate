//
//  QuranPDFView.swift
//  Quran annotate
//
//  Created by Macbook Air on 06/11/2025.
//

import SwiftUI
import PDFKit
import PencilKit

// UIViewRepresentable pour intégrer PDFView avec support complet des annotations
struct PDFKitView: UIViewRepresentable {
    let pdfDocument: PDFDocument
    @Binding var currentPage: Int

    class Coordinator: NSObject {
        var parent: PDFKitView
        var observer: NSObjectProtocol?

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPDFPage = pdfView.currentPage else {
                return
            }

            let index = parent.pdfDocument.index(for: currentPDFPage)
            DispatchQueue.main.async {
                self.parent.currentPage = index
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()

        // Configuration de base
        pdfView.document = pdfDocument
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal

        // Configuration RTL (Right-to-Left pour l'arabe)
        pdfView.displaysRTL = true

        // Arrière-plan
        pdfView.backgroundColor = UIColor.systemBackground

        // Observer les changements de page
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { notification in
            context.coordinator.pageChanged(notification)
        }

        // Aller à la page initiale
        if let page = pdfDocument.page(at: currentPage) {
            pdfView.go(to: page)
        }

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Mettre à jour le parent dans le coordinator
        context.coordinator.parent = self

        // Mettre à jour la page si elle a changé
        if let page = pdfDocument.page(at: currentPage),
           pdfView.currentPage != page {
            UIView.animate(withDuration: 0.3) {
                pdfView.go(to: page)
            }
        }
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// Vue principale du Coran avec contrôles
struct QuranPDFView: View {
    @StateObject private var viewModel = QuranPDFViewModel()
    @State private var isAnnotationMode = false
    @State private var showPageSelector = false
    @State private var drawings: [Int: PKDrawing] = [:] // Dessins par page

    var body: some View {
        ZStack {
            // Vue PDF avec annotations et page curl natif
            if let document = viewModel.pdfDocument {
                QuranPageCurlView(
                    pdfDocument: document,
                    currentPage: $viewModel.currentPage,
                    isAnnotationMode: $isAnnotationMode,
                    isLandscape: $viewModel.isLandscape,
                    drawings: $drawings
                )
                .id(viewModel.isLandscape) // Forcer recréation quand l'orientation change
                .edgesIgnoringSafeArea(.all)
            } else {
                // Vue de chargement
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Chargement du Coran...")
                        .font(.headline)
                        .padding(.top)
                }
            }

            // Overlay des contrôles
            VStack {
                // Barre supérieure
                HStack {
                    // Bouton mode annotation
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

                    Spacer()

                    // Indicateur de page
                    Button(action: {
                        showPageSelector.toggle()
                    }) {
                        Text("صفحة \(viewModel.currentPage + 1) / \(viewModel.totalPages)")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(.systemBackground).opacity(0.8))
                            .cornerRadius(20)
                            .shadow(radius: 2)
                    }

                    Spacer()

                    // Bouton info
                    Button(action: {
                        // Action info
                    }) {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundColor(.primary)
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
        .sheet(isPresented: $showPageSelector) {
            PageSelectorView(
                currentPage: $viewModel.currentPage,
                totalPages: viewModel.totalPages,
                isPresented: $showPageSelector
            )
        }
        .environment(\.layoutDirection, .rightToLeft)
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
