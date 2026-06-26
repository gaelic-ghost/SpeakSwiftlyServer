import Foundation
import Hummingbird

package enum HTTPWebUIRoutes {
    package static let routePrefix = "/control-panel"
    package static let resourceSubdirectory = "WebUI"
}

package func registerHTTPWebUIRoutes(on router: Router<BasicRequestContext>) {
    guard let webUIRoot = Bundle.module.url(
        forResource: "index",
        withExtension: "html",
        subdirectory: HTTPWebUIRoutes.resourceSubdirectory,
    )?.deletingLastPathComponent()
    else {
        return
    }

    router.middlewares.add(
        FileMiddleware(
            webUIRoot.path,
            urlBasePath: HTTPWebUIRoutes.routePrefix,
            searchForIndexHtml: true,
        ),
    )
}
