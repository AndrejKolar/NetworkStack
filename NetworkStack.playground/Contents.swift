/*: Description
 # NetworkStack
 Clean and simple networking stack
 */
import UIKit
import PlaygroundSupport

// Types

enum Result<T> {
    case success(T)
    case error(Error)
}

typealias ResultCallback<T> = (Result<T>) -> Void

enum NetworkStackError: Error {
    case invalidRequest
    case dataMissing
    case mockMissing
}

// Webservice

protocol WebserviceProtocol {
    func request<T: Decodable>(_ endpoint: Endpoint, completition: @escaping ResultCallback<T>)
}

class Webservice: WebserviceProtocol {
    private let urlSession: URLSession
    private let parser: Parser
    private let networkActivity: NetworkActivityProtocol
    
    init(urlSession: URLSession = URLSession(configuration: URLSessionConfiguration.default),
         parser: Parser = Parser(),
         networkActivity: NetworkActivityProtocol = NetworkActivity()) {
        self.urlSession = urlSession
        self.parser = parser
        self.networkActivity = networkActivity
    }
    
    func request<T: Decodable>(_ endpoint: Endpoint, completition: @escaping ResultCallback<T>) {
        
        guard let request = endpoint.request else {
            OperationQueue.main.addOperation({ completition(.error(NetworkStackError.invalidRequest)) })
            return
        }
        
        networkActivity.increment()
        
        let task = urlSession.dataTask(with: request) { [unowned self] (data, response, error) in
            
            self.networkActivity.decrement()
            
            if let error = error {
                OperationQueue.main.addOperation({ completition(.error(error)) })
                return
            }
            
            guard let data = data else {
                OperationQueue.main.addOperation({ completition(.error(NetworkStackError.dataMissing)) })
                return
            }
            
            self.parser.json(data: data, completition: completition)
        }
        
        task.resume()
    }
    
    func mockRequest<T: Decodable>(_ endpoint: Endpoint, completition: @escaping ResultCallback<T>) {
        guard let data = endpoint.mockData() else {
            OperationQueue.main.addOperation({ completition(.error(NetworkStackError.mockMissing)) })
            return
        }
        
        parser.json(data: data, completition: completition)
    }
}

// Network Activity

protocol NetworkActivityProtocol {
    func increment()
    func decrement()
}

class NetworkActivity: NetworkActivityProtocol {
    private var activityCount: Int = 0 {
        didSet {
            UIApplication.shared.isNetworkActivityIndicatorVisible = (activityCount > 0)
        }
    }
    
    func increment() {
        OperationQueue.main.addOperation({ self.activityCount += 1 })
    }
    
    func decrement() {
        OperationQueue.main.addOperation({ self.activityCount -= 1 })
    }
}

// Parser

protocol ParserProtocol {
    func json<T: Decodable>(data: Data, completition: @escaping ResultCallback<T>)
}

struct Parser {
    let jsonDecoder = JSONDecoder()
    
    func json<T: Decodable>(data: Data, completition: @escaping ResultCallback<T>) {
        do {
            let result: T = try jsonDecoder.decode(T.self, from: data)
            OperationQueue.main.addOperation { completition(.success(result)) }
            
        } catch let parseError {
            OperationQueue.main.addOperation { completition(.error(parseError)) }
        }
    }
}

// Endpoint

protocol Endpoint {
    var request: URLRequest? { get }
    var httpMethod: String { get }
    var queryItems: [URLQueryItem]? { get }
    var scheme: String { get }
    var host: String { get }
    var mockFilename: String? { get }
    var mockExtension: String? { get }
}

extension Endpoint {
    func request(forEndpoint endpoint: String) -> URLRequest? {
        
        var urlComponents = URLComponents()
        urlComponents.scheme = scheme
        urlComponents.host = host
        urlComponents.path = endpoint
        urlComponents.queryItems = queryItems
        guard let url = urlComponents.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        if let httpHeaders = httpHeaders {
            for (key,value) in httpHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        return request
    }
    
    func mockData() -> Data? {
        guard let mockFileUrl = Bundle.main.url(forResource: mockFilename, withExtension: mockExtension),
            let mockData = try? Data(contentsOf: mockFileUrl) else {
                return nil
        }
        return mockData
    }
}

extension Endpoint {
    var scheme: String {
        return "http"
    }
    
    var host: String {
        return "www.mocky.io"
    }
    
    var queryItems: [URLQueryItem]? {
        return nil
    }
    
    var httpHeaders: [String: String]? {
        return nil
    }
    
    var mockFilename: String? {
        return  nil
    }
    
    var mockExtension: String? {
        return "json"
    }
}

// UserEndpoint

enum UserEndpoint {
    case all
    case get(userId: Int)
}

extension UserEndpoint: Endpoint {
    
    var request: URLRequest? {
        switch self {
        case .all:
            return request(forEndpoint: "/v2/58177efc1000008c01cc7fc2")
        case .get(_):
            return request(forEndpoint: "/v2/58177ddc1000008901cc7fbf")
        }
    }
    
    var httpMethod: String {
        switch self {
        case .all:
            return "GET"
        case .get( _):
            return "GET"
        }
    }
    
    var queryItems: [URLQueryItem]? {
        switch self {
        case .all:
            return nil
        case .get(let userId):
            return [URLQueryItem(name: "userId", value: String(userId))]
        }
    }
    
    var httpHeaders: [String: String]? {
        let defaultHeaders: [String: String] = [:]
        switch self {
        case .all:
            return defaultHeaders
        case .get(let userId):
            return defaultHeaders
        }
    }
    
    var mockFilename: String? {
        switch self {
        case .all:
            return "users"
        case .get( _):
            return "user"
        }
    }
}

// User

struct User: Codable {
    let id: Int
    let username: String
    let email: String
}

// Playground

PlaygroundPage.current.needsIndefiniteExecution = true

// Run

let webservice = Webservice()

webservice.request(UserEndpoint.all) { (result: Result<[User]>) in
    switch result {
    case .error(let error):
        dump(error)
    case .success(let users):
        dump(users)
    }
}

webservice.request(UserEndpoint.get(userId: 10)) { (result: Result<User>) in
    switch result {
    case .error(let error):
        dump(error)
    case .success(let users):
        dump(users)
    }
}

webservice.mockRequest(UserEndpoint.get(userId: 10)) { (result: Result<User>) in
    switch result {
    case .error(let error):
        dump(error)
    case .success(let users):
        dump(users)
    }
}

webservice.mockRequest(UserEndpoint.all) { (result: Result<[User]>) in
    switch result {
    case .error(let error):
        dump(error)
    case .success(let users):
        dump(users)
    }
}

