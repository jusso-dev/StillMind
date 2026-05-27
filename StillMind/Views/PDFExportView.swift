import SwiftUI

/// View for configuring and triggering a PDF export of journal entries.
struct PDFExportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProjectId: UUID?
    @State private var availableProjects: [Project] = []
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var filterByDate = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()

    private let entryRepository: EntryRepository
    private let projectRepository: ProjectRepository
    private let pdfService: PDFExportService

    init(entryRepository: EntryRepository, projectRepository: ProjectRepository) {
        self.entryRepository = entryRepository
        self.projectRepository = projectRepository
        self.pdfService = PDFExportService(entryRepository: entryRepository, projectRepository: projectRepository)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Project", selection: $selectedProjectId) {
                        Text("All Entries").tag(UUID?.none)
                        ForEach(availableProjects) { project in
                            Text(project.name).tag(UUID?.some(project.id))
                        }
                    }

                    Toggle("Filter by date", isOn: $filterByDate)

                    if filterByDate {
                        DatePicker("From", selection: $startDate, displayedComponents: .date)
                        DatePicker("To", selection: $endDate, displayedComponents: .date)
                    }
                } header: {
                    Text("What to export")
                }

                Section {
                    Button {
                        Haptics.medium()
                        Task { await exportPDF() }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Export PDF", systemImage: "doc.richtext")
                                .font(.headline)
                                .foregroundStyle(Color.smAccent)
                            Spacer()
                        }
                    }
                    .disabled(isExporting)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Your exported journal includes transcripts, summaries, and mood reflections. Save it somewhere safe — it's unencrypted.")
                }
            }
            .navigationTitle("Export Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)
                }
            }
            .overlay {
                if isExporting {
                    ZStack {
                        Color(.systemBackground).opacity(0.8)
                            .ignoresSafeArea()

                        VStack(spacing: Spacing.md) {
                            ProgressView()
                                .tint(Color.smAccent)

                            Text("Creating your journal...")
                                .font(.subheadline.weight(.medium))

                            Text("This may take a moment")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(Spacing.xl)
                        .background(.regularMaterial, in: .rect(cornerRadius: 20))
                    }
                }
            }
            .allowsHitTesting(!isExporting)
            .task {
                availableProjects = (try? await projectRepository.allProjects()) ?? []
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func exportPDF() async {
        isExporting = true
        errorMessage = nil
        do {
            let dateRange: ClosedRange<Date>? = filterByDate ? startDate...endDate : nil
            let url = try await pdfService.exportToPDF(projectId: selectedProjectId, dateRange: dateRange)
            exportedURL = url
            Haptics.success()
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isExporting = false
    }
}

/// UIKit share sheet wrapper for SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
