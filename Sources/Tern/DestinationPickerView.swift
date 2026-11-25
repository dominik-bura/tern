import SwiftUI

struct DestinationPickerView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: RoutingCoordinator
    @State private var selection: BrowserDestination?
    @State private var remember = false

    private var destinations: [BrowserDestination] {
        model.browsers.flatMap { browser in [.browser(browser.id)] + model.profileItems(of: browser).map(\.destination) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let pending = router.current {
                header(pending)
                List(selection: $selection) {
                    ForEach(model.browsers) { browser in
                        row(.browser(browser.id), name: browser.name)
                        ForEach(model.profileItems(of: browser)) { item in
                            row(item.destination, name: item.name).padding(.leading, 28)
                        }
                    }
                }
                .contextMenu(forSelectionType: BrowserDestination.self, menu: { _ in }) { items in
                    if let destination = items.first { open(destination) }
                }
                Divider()
                footer(pending)
            } else {
                ContentUnavailableView("No Pending Links", systemImage: "link")
            }
        }
        .frame(width: 400, height: 480)
        .disabled(router.isDelivering)
        .onAppear { selection = selection ?? destinations.first }
        .onChange(of: router.current?.id) { _, _ in remember = false }
    }

    private func header(_ pending: RoutingCoordinator.Pending) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pending.request.url.host ?? "Link").font(.headline)
                Spacer()
                if router.isDelivering { ProgressView().controlSize(.small) }
                Button { copy(pending.request.url) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy Link").accessibilityLabel("Copy Link")
            }
            Text(pending.request.url.absoluteString)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            if let error = pending.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func row(_ destination: BrowserDestination, name: String) -> some View {
        HStack(spacing: 8) {
            DestinationIcon(destination: destination, size: 20)
            Text(name)
        }
        .tag(destination)
        .padding(.vertical, 2)
    }

    private func footer(_ pending: RoutingCoordinator.Pending) -> some View {
        HStack(spacing: 8) {
            Toggle("Always open \(pending.request.url.host ?? "this site") here", isOn: $remember)
                .toggleStyle(.checkbox).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if router.queuedCount > 0 {
                Text("+\(router.queuedCount)").font(.callout).foregroundStyle(.secondary)
                    .help("\(router.queuedCount) more links waiting")
            }
            Button("Cancel") { router.cancel() }.keyboardShortcut(.cancelAction)
            if pending.error != nil, pending.decision.destination != .ask {
                Button("Retry") { router.retry() }
            }
            Button("Open") { if let selection { open(selection) } }
                .keyboardShortcut(.defaultAction).disabled(selection == nil)
        }
        .nativeButtonStyle()
        .padding(16)
    }

    private func open(_ destination: BrowserDestination) {
        if remember, let host = router.current?.request.url.host {
            model.remember(host: host, destination: destination)
        }
        router.choose(destination)
    }

    private func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}
