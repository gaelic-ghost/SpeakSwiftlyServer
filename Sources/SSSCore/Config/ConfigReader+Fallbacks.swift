import Configuration
import Foundation

package extension ConfigReader {
    func requiredBool(forKey key: ConfigKey, fallback: Bool) throws -> Bool {
        do {
            return try requiredBool(forKey: key)
        } catch {
            guard error.isMissingRequiredConfigValue else { throw error }

            return fallback
        }
    }

    func requiredString(forKey key: ConfigKey, fallback: String) throws -> String {
        do {
            return try requiredString(forKey: key)
        } catch {
            guard error.isMissingRequiredConfigValue else { throw error }

            return fallback
        }
    }

    func requiredInt(forKey key: ConfigKey, fallback: Int) throws -> Int {
        do {
            return try requiredInt(forKey: key)
        } catch {
            guard error.isMissingRequiredConfigValue else { throw error }

            return fallback
        }
    }

    func requiredDouble(forKey key: ConfigKey, fallback: Double) throws -> Double {
        do {
            return try requiredDouble(forKey: key)
        } catch {
            guard error.isMissingRequiredConfigValue else { throw error }

            return fallback
        }
    }
}

private extension Error {
    var isMissingRequiredConfigValue: Bool {
        String(describing: self).contains("Missing required config value for key:")
    }
}
