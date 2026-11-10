import SwiftUI

/// Adds a course section for the selected term. The section (CRN) and
/// instructor are required so syllabus dates stay tied to the exact section.
struct AddCourseView: View {
    @EnvironmentObject private var store: CourseCompanionStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.schoolTheme) private var theme

    @State private var subject = ""
    @State private var number = ""
    @State private var title = ""
    @State private var sectionCode = ""
    @State private var instructor = ""
    @State private var origin = "manual"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field { case subject, number, title, section, instructor }

    private var term: AcademicTerm? { store.selectedTerm }
    private var sectionLabel: String { theme.slug == SchoolTheme.virginiaTech.slug ? "CRN" : "Section" }

    /// Courses from the student's imported transcript for this term, if any.
    private var suggestions: [InProgressCourse] {
        guard let term else { return [] }
        let added = Set(store.courses.map(\.code))
        return (appState.inProgressCourses + appState.plannedCourses)
            .filter { $0.semester == term.name && !added.contains($0.code) }
    }

    private var canSave: Bool {
        !subject.isEmpty && !number.isEmpty && !sectionCode.isEmpty
            && !instructor.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgoraSpacing.xl) {
                    if !suggestions.isEmpty { suggestionList }

                    VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                        SectionLabel(title: "Course", icon: "book")
                        HStack(spacing: AgoraSpacing.md) {
                            TextField("Subject (CS)", text: $subject)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .focused($focused, equals: .subject)
                                .agoraField()
                            TextField("Number (2114)", text: $number)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .focused($focused, equals: .number)
                                .agoraField()
                        }
                        TextField("Course title (optional)", text: $title)
                            .focused($focused, equals: .title)
                            .agoraField()
                    }

                    VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                        SectionLabel(title: "Your section", icon: "number")
                        TextField(sectionLabel, text: $sectionCode)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .section)
                            .agoraField()
                            .accessibilityHint("The section identifier from your schedule")
                        TextField("Instructor", text: $instructor)
                            .textContentType(.name)
                            .focused($focused, equals: .instructor)
                            .agoraField()
                        Text("Use the \(sectionLabel) and instructor from your \(term?.name ?? "") schedule. Exam dates and office hours often differ by section, so Agora keeps them tied to this one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Add course") }
                    }
                    .buttonStyle(.agoraPrimary)
                    .disabled(!canSave)
                }
                .padding(.horizontal, 20)
                .padding(.top, AgoraSpacing.lg)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .hokieScreenBackground()
            .safeAreaInset(edge: .top) {
                HokieSheetHeader(title: "Add a course", subtitle: term?.name ?? "", symbol: "plus", accent: theme.accent) {
                    Button("Cancel") { dismiss() }
                        .font(.body.weight(.medium))
                        .frame(minHeight: 44)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "From your transcript", icon: "doc.text")
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, course in
                    if index > 0 { Divider().padding(.leading, AgoraSpacing.lg) }
                    Button {
                        let parts = course.code.split(separator: " ")
                        subject = parts.first.map(String.init) ?? ""
                        number = parts.dropFirst().joined()
                        title = course.name
                        origin = "transcript"
                        focused = .section
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.code).font(.subheadline.weight(.semibold))
                                Text(course.name).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle").foregroundStyle(theme.accentText)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, AgoraSpacing.lg)
                        .padding(.vertical, AgoraSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Fills in the course; you'll still add your section and instructor")
                }
            }
            .glassSurface(cornerRadius: AgoraRadius.card)
        }
    }

    private func save() async {
        guard let term else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await store.addCourse(.init(
                termKey: term.termKey,
                subject: subject.trimmingCharacters(in: .whitespaces).uppercased(),
                number: number.trimmingCharacters(in: .whitespaces).uppercased(),
                title: title.trimmingCharacters(in: .whitespaces),
                sectionCode: sectionCode.trimmingCharacters(in: .whitespaces),
                instructorName: instructor.trimmingCharacters(in: .whitespaces),
                origin: origin
            ))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
