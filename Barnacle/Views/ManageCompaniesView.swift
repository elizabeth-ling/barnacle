import SwiftUI
import SwiftData

/// The lightweight company management the spec asks for (spec `03`, "Managing companies"):
/// see what's tracked, pause a company so the scrape loop skips it, or remove one.
///
/// Deliberately not a CRUD screen — there's no editing here. Reached from the Feed's company
/// filter, which is where tracked companies are already visible.
struct ManageCompaniesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Company.name) private var companies: [Company]

    /// Every posting, counted in memory per company — the same one-user scale that lets the
    /// Feed sort in memory, and the remove dialog needs the count anyway.
    @Query private var postings: [JobPosting]

    @State private var pendingRemoval: Company?

    private var isRemoving: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            Text("Manage companies")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Hairline()

            if companies.isEmpty {
                Text("No companies yet. Add one with the + button on the Feed.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(companies) { company in
                            row(for: company)
                            Hairline()
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            Hairline()

            HStack {
                Spacer(minLength: 8)
                Button("Done") { dismiss() }
                    .buttonStyle(.barnacleSecondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(width: 460)
        .background(Theme.Palette.surface)
        // A sheet is its own window — same light-only caveat as `RootView`.
        .preferredColorScheme(.light)
        .confirmationDialog(
            pendingRemoval.map { "Remove \($0.name)?" } ?? "Remove company?",
            isPresented: isRemoving,
            presenting: pendingRemoval
        ) { company in
            // Keeping the postings is the default the spec asks for, so it comes first.
            Button("Remove, keep postings") { remove(company, deletingPostings: false) }
            Button("Remove and delete \(postingCount(for: company)) postings", role: .destructive) {
                remove(company, deletingPostings: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: { company in
            Text("Barnacle stops checking \(company.name). Its stored postings can stay in the feed.")
        }
    }

    private func row(for company: Company) -> some View {
        CompactRow(title: company.name, metadata: metadata(for: company)) {
            HStack(spacing: 6) {
                Button(company.isActive ? "Active" : "Paused") {
                    company.isActive.toggle()
                }
                .buttonStyle(.quietControl(isActive: company.isActive))
                .help(company.isActive ? "Skip this company on the next scrape" : "Include this company again")

                Button {
                    pendingRemoval = company
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.quietControl())
                .help("Remove this company")
            }
        }
    }

    private func metadata(for company: Company) -> String {
        var parts = [company.atsType.displayName]
        if company.careerURLs.count > 1 {
            parts.append("\(company.careerURLs.count) URLs")
        }
        let count = postingCount(for: company)
        parts.append(count == 1 ? "1 posting" : "\(count) postings")
        return parts.joined(separator: " \u{00B7} ")
    }

    private func postingCount(for company: Company) -> Int {
        postings.filter { $0.companyID == company.id }.count
    }

    /// Postings are kept by default (§5 never deletes them), so discarding is the explicit choice.
    private func remove(_ company: Company, deletingPostings: Bool) {
        if deletingPostings {
            for posting in postings where posting.companyID == company.id {
                modelContext.delete(posting)
            }
        }
        modelContext.delete(company)
        try? modelContext.save()
        pendingRemoval = nil
    }
}

#Preview("Manage companies") {
    ManageCompaniesView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
