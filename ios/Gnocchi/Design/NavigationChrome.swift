import SwiftUI
import UIKit

@MainActor
@Observable
final class NavigationChrome {
    private var surfaceSuppressesActions = false
    private var visibleRecipeDetails: Set<UUID> = []

    var actionsSuppressed: Bool { surfaceSuppressesActions || !visibleRecipeDetails.isEmpty }
    private(set) var addCookbook: (() -> Void)?

    func hideActions() {
        surfaceSuppressesActions = true
        addCookbook = nil
    }

    func showActions(addCookbook: (() -> Void)?) {
        surfaceSuppressesActions = false
        self.addCookbook = addCookbook
    }

    func setRecipeDetailVisible(_ visible: Bool, id: UUID) {
        if visible {
            visibleRecipeDetails.insert(id)
        } else {
            visibleRecipeDetails.remove(id)
        }
    }
}

extension View {
    func navigationActionSurface(addCookbook: (() -> Void)? = nil) -> some View {
        modifier(NavigationActionSurface(addCookbook: addCookbook))
    }
}

private struct NavigationActionSurface: ViewModifier {
    @Environment(NavigationChrome.self) private var chrome

    let addCookbook: (() -> Void)?

    func body(content: Content) -> some View {
        content.background {
            NavigationSurfaceObserver { visible in
                if visible {
                    chrome.showActions(addCookbook: addCookbook)
                }
            }
            .frame(width: 0, height: 0)
        }
    }
}

private struct NavigationSurfaceObserver: UIViewControllerRepresentable {
    let onVisibility: (Bool) -> Void

    func makeUIViewController(context: Context) -> SurfaceController {
        SurfaceController(onVisibility: onVisibility)
    }

    func updateUIViewController(_ controller: SurfaceController, context: Context) {
        controller.onVisibility = onVisibility
    }

    final class SurfaceController: UIViewController {
        var onVisibility: (Bool) -> Void

        init(onVisibility: @escaping (Bool) -> Void) {
            self.onVisibility = onVisibility
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            onVisibility(true)
        }

    }
}
