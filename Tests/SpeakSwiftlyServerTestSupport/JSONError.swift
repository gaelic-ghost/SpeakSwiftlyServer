package enum JSONError: Error {
    case notDictionary
    case notArray
    case emptyBody(String)
}
