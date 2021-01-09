import UIKit

// MARK: - Description

// Protocols aka Concepts
// Protocols are fo reusable algorithms.
// PAT = Protocol with Associated Type




// MARK: - Variables

// Required for the urlRequest creation
var baseURL = URL(string: "my.awesome.base.url")!




// MARK: - Models

// Model Protocols

// We use static for `apiBase` because we want to be able to access it only using the `Fetchable` type, not a concrete object/implementation
protocol Fetchable: Decodable {
    static var apiBase: String { get }
    associatedtype ID: IDType
    var id: ID { get }
}

protocol IDType: Codable, Hashable {
    // `Value` is a Generic. We can have any kind of value here (i.e. Int, String)

    // DO NOT use Any. It exists 'cause it has to, but you shouldn't use it almost anywhere in your code.
    // `Any` should only be used when you don't care what type is there, when any type in the entire system works.
    // When you use associatedtype, you should know that you WON'T be able to put these things into an array in the future.
    associatedtype Value

    var value: Value { get }
    init(value: Value)
}
extension IDType {
    init(_ value: Value) { self.init(value: value) }
}

// Concrete Models

// Codable = Decodable & Encodable
// Hashable means able to produce an integer hashed value
// If you have a struct that conforms to Codable/Hashable, all its properties have to do the same.
struct User: Codable, Hashable {
    struct ID: IDType { let value: Int }
    var id: ID
    var name: String
}
extension User: Fetchable {
    static var apiBase: String { return "user" }
}

struct Document: Codable, Hashable {
    struct ID: IDType { let value: String }
    var id: ID
    var title: String
}
extension Document: Fetchable {
    static var apiBase: String { return "document" }
}


// MARK: - Networking layer

// A protocol does not conform to itself. This is intended and safe behaviour.
protocol Transport {
    func fetch(request: URLRequest,
               completion: @escaping (Result<Data, Error>) -> Void)
}

// We use class because it's a Singleton
class NetworkTransporter: Transport {
    static let shared = NetworkTransporter()
    private var session = URLSession.shared

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        session.dataTask(with: request) {
            (data, _, error) in
                if let error = error {
                    completion(.failure(error))
                } else if let data = data {
                    completion(.success(data))
                }
        }.resume()
    }
}

// Just needed one place where to make use of all the things above
struct Client {
    let transport: Transport

    init(transport: Transport = NetworkTransporter.shared) {
        self.transport = transport
    }

    func fetch<Model: Fetchable>(_: Model.Type,
                                 id: Model.ID,
                                 completion: @escaping (Result<Model, Error>) -> Void) {

        let urlRequest = URLRequest(url: baseURL
                                        .appendingPathComponent(Model.apiBase)
                                        .appendingPathComponent("\(id.value)"))

        transport.fetch(request: urlRequest) { data in
            // `.get()` returns the success value as a throwing expression.
            completion( Result {
                return try JSONDecoder().decode(Model.self, from: data.get())
            })

            // Otherwise use the classic switch method below
//            switch result {
//            case .success(let data):
//                completion( Result {
//                    try JSONDecoder().decode(Model.self, from: data)
//                })
//            case .failure(let error):
//                completion(.failure(error))
//            }
        }
    }
}




// MARK: - Code usage
// Basically how can I make use of all things above.

// Just a helper so I won't write this again and again
// This is able to print any Fetchable model.
func handleResult<Model: Fetchable>(_ result: Result<Model, Error>) {
    // Used `Model.Type` to get the concrete type of the `Fetchable` model.
    // Added `.self` so I can have an instance to apply the hidden description property to.
    switch result {
    case .success(let object):
        print("Successfully fetched object of type \(Model.Type.self) with the body \(object)")
    case .failure(let error):
        print("Failed to fetch object of type \(Model.Type.self) with error \(error)")
    }
}

let client = Client()
// Here's the magic. Using the same function for 2 different object types: User and Document.
client.fetch(User.self, id: User.ID(1)) { result in
    handleResult(result)
}
client.fetch(Document.self, id: Document.ID("1")) { result in
    handleResult(result)
}




// MARK: - Being fancy with Transport

// This struct is basically taking an existent concrete `Transport` object and doing stuff with it.
// A great solution for in depth testing without mocks.
struct AddHeaders: Transport {
    func fetch(request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        var newRequest = request
        for (key, value) in headers {
            newRequest.addValue(value, forHTTPHeaderField: key)
        }
        base.fetch(request: newRequest, completion: completion)
    }

    // The type of `base` is `Existential`. It's a little box created by the compiler (basically the protocol is wrapped in this)
    let base: Transport
    var headers: [String: String]
}

let transport = AddHeaders(base: NetworkTransporter.shared,
                           headers: ["Authorization" : "..."])





// MARK: - How the compiler behaves with generics

// This creates multiple versions of the `process` method for each different Transport.
func process<T: Transport>(transport: T) {}

// This creates a single version of `process`, ignoring any kind of concrete implementation of Transport.
func process(transport: Transport) {}




// MARK: - Generic technique that works as alternative for protocol arrays

struct RefreshRequests {
    // Closure - acts like a property, but has a function body, so it's a consumer in the end.
    let perform: () -> Void
}
extension RefreshRequests {
    init(userID: User.ID) {
        self.init(perform: { refresh(User.self, id: userID) })
    }

    init(documentID: Document.ID) {
        self.init(perform: { refresh(Document.self, id: documentID) })
    }
}

let refreshes = [RefreshRequests(userID: User.ID(4)),
                 RefreshRequests(documentID: Document.ID("myid"))]

for refresh in refreshes {
    refresh.perform()
}

func refresh<Model: Fetchable>(_ model: Model.Type,
                               id: Model.ID) {
    Client().fetch(model, id: id) { handleResult($0) }
}




// MARK: Being fancy with URL Requests

// The most concrete code ever - pure data
struct Request {
    let urlRequest: URLRequest
    let completion: (Result<Data, Error>) -> Void
}
extension Request {
    static func fetching<Model: Fetchable>(_: Model.Type,
                                           id: Model.ID,
                                           completion: @escaping (Result<Model, Error>) -> Void) -> Request {
        let urlRequest = URLRequest(url: baseURL
                                        .appendingPathComponent(Model.apiBase)
                                        .appendingPathComponent("\(id.value)"))

        return self.init(urlRequest: urlRequest) { data in
            completion( Result {
                return try JSONDecoder().decode(Model.self, from: data.get())
            })
        }
    }
}

// Simple method to fetch a custom `Request`
func fetch(request: Request, withTransport transport: Transport = NetworkTransporter.shared) {
    transport.fetch(request: request.urlRequest,
                    completion: request.completion)
}

// Now I can store an array of requests that failed or that I want to handle somehow
let userRequest = Request.fetching(User.self, id: User.ID(2),
                                   completion: handleResult(_:))
let documentRequest = Request.fetching(Document.self, id: Document.ID("2"),
                                       completion: handleResult(_:))

let myRequestsArray = [userRequest, documentRequest]
myRequestsArray.forEach { fetch(request: $0) }




// MARK: - Processing arrays of protocols

protocol File {
    var path: String { get set }
    func isEqual(to: File) -> Bool
}
// This allows us to write an implementation for all the objects that conform to File and Equatable
// instead of having one for each concrete type.
// Self is playint the role of the concrete type here.
extension File where Self: Equatable {
    func isEqual(to other: File) -> Bool {
        guard let other = other as? Self else {
            return false
        }
        return self == other
    }
}

// MARK: Concrete types implementation
struct TextFile: File, Equatable {
    var path: String
    var content: String
}

struct SpreadSheet: File, Equatable {
    var path: String
    var cells: [String: String]
}

// MARK: Code usage
let password = TextFile(path: "/foo/password",
                            content: "...")
let budget = SpreadSheet(path: "/bar/budget/",
                         cells: ["A1": "$52"])

let docs: [File] = [password, budget]
docs.contains { $0.isEqual(to: password) }

// This allows us to override the implementation for `contains` method
// in arrays with File type elements.
// NOT conforming to File (Element: File), but actual File elements (Element == File).
// Will not work for [TextFile] or [SpreadSheet], only for [File]
extension Sequence where Element == File {
    func contains(_ element: Element) -> Bool {
        return contains { $0.isEqual(to: element) }
    }
}

// Now I can use `contains` without the explicit implementation
docs.contains(password)

