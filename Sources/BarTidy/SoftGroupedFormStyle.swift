import SwiftUI

/// Keep native Form sections and controls, with spacing instead of rules.
struct SoftGroupedFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(sections: configuration.content) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        section.header
                            .padding(.horizontal, 12)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)

                        VStack(spacing: 0) {
                            ForEach(subviews: section.content) { row in
                                row
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .transition(.identity)
                            }
                        }
                        .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityElement(children: .contain)
                    }
                    .transition(.identity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
