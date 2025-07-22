import Foundation

protocol AppError: LocalizedError {
    var title: String { get }
    var typeIdentifier: String { get }
}
