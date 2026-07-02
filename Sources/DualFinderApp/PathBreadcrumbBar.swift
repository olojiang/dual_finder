import SwiftUI

struct PathBreadcrumbBar: View {
    let components: [PathBreadcrumbComponent]
    let onSelect: (URL) -> Void
    let onEditPath: () -> Void

    private var visibleComponents: ArraySlice<PathBreadcrumbComponent> {
        components.suffix(4)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                if components.count > visibleComponents.count {
                    Text("...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 2)
                }
                ForEach(Array(visibleComponents.enumerated()), id: \.element.id) { index, component in
                    if index > 0 || components.count > visibleComponents.count {
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
                    .foregroundStyle(component == components.last ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(component.url.path)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
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
        var depth = 0

        while depth < 64 {
            let title = displayTitle(for: current)
            parts.append(PathBreadcrumbComponent(url: current, title: title))
            if current.path == "/" {
                break
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || parent.path.isEmpty || parent.path == ".." {
                break
            }
            current = parent
            depth += 1
        }
        return parts.reversed()
    }

    private static func displayTitle(for url: URL) -> String {
        if url.path == "/" {
            return "/"
        }
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}
