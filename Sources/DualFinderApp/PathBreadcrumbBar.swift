import SwiftUI

struct PathBreadcrumbBar: View {
    let components: [PathBreadcrumbComponent]
    let onSelect: (URL) -> Void
    let onEditPath: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
                        if index > 0 {
                            Text(">")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 2)
                        }
                        Button(component.title) {
                            onSelect(component.url)
                        }
                        .buttonStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(index == components.count - 1 ? .primary : .secondary)
                        .lineLimit(1)
                        .help(component.url.path)
                    }
                }
            }
            Button(action: onEditPath) {
                Image(systemName: "pencil")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Edit path")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PathBreadcrumbComponent: Identifiable, Equatable {
    let url: URL
    let title: String

    var id: String { url.path }
}

enum PathBreadcrumbBuilder {
    static func components(for url: URL) -> [PathBreadcrumbComponent] {
        let standardized = url.standardizedFileURL
        var parts: [PathBreadcrumbComponent] = []
        var current = standardized

        while true {
            let title = displayTitle(for: current)
            parts.insert(PathBreadcrumbComponent(url: current, title: title), at: 0)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || parent.path.isEmpty {
                break
            }
            current = parent
        }
        return parts
    }

    private static func displayTitle(for url: URL) -> String {
        if url.path == "/" {
            return "/"
        }
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}
