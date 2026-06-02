import Foundation

package enum GenerationLocation: Equatable {
    case local
    case remote(RemoteGenerationService)
}

package struct RemoteGenerationService: Decodable, Equatable {
    package let baseURL: String
    package let serviceName: String?

    enum CodingKeys: String, CodingKey {
        case baseURL
        case baseURLSnake = "base_url"
        case serviceName
        case serviceNameSnake = "service_name"
    }

    package init(baseURL: String, serviceName: String? = nil) {
        self.baseURL = baseURL
        self.serviceName = serviceName
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURLSnake)
            ?? container.decode(String.self, forKey: .baseURL)
        serviceName = try container.decodeIfPresent(String.self, forKey: .serviceNameSnake)
            ?? container.decodeIfPresent(String.self, forKey: .serviceName)
    }
}

extension GenerationLocation: Decodable {
    enum CodingKeys: String, CodingKey {
        case kind
        case remote
    }

    package init(from decoder: any Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let rawValue = try? singleValue.decode(String.self) {
            switch rawValue {
                case "local":
                    self = .local
                default:
                    throw DecodingError.dataCorruptedError(
                        in: singleValue,
                        debugDescription: "Generation location '\(rawValue)' is not supported. Use 'local' or an object with kind 'remote'.",
                    )
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
            case "local":
                self = .local
            case "remote":
                self = try .remote(container.decode(RemoteGenerationService.self, forKey: .remote))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "Generation location kind '\(kind)' is not supported. Use 'local' or 'remote'.",
                )
        }
    }
}
