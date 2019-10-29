/*: Description
 # NetworkStack
 Clean and simple networking stack
 */
import UIKit
import PlaygroundSupport

// Types

typealias ResultCallback<T> = (Result<T, NetworkStackError>) -> Void

enum NetworkStackError: Error {
    case invalidRequest
    case dataMissing
    case endpointNotMocked
    case mockDataMissing
    case responseError(error: Error)
    case parserError(error: Error)
}

// WebService

protocol WebServiceProtocol {
    func request<T: Decodable>(_ endpoint: Endpoint, completition: @escaping ResultCallback<T>)
}

class WebService: WebServiceProtocol {
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
            OperationQueue.main.addOperation({ completition(.failure(NetworkStackError.invalidRequest)) })
            return
        }
        
        networkActivity.increment()
        
        let task = urlSession.dataTask(with: request) { [unowned self] (data, response, error) in
            
            self.networkActivity.decrement()
            
            if let error = error {
                OperationQueue.main.addOperation({ completition(.failure(.responseError(error: error))) })
                return
            }
            
            guard let data = data else {
                OperationQueue.main.addOperation({ completition(.failure(NetworkStackError.dataMissing)) })
                return
            }
            
            self.parser.json(data: data, completition: completition)
        }
        
        task.resume()
    }
}

// Mock WebService

class MockWebService: WebServiceProtocol {
    private let parser: Parser
    
    init(parser: Parser = Parser()) {
        self.parser = parser
    }
    
    func request<T: Decodable>(_ endpoint: Endpoint, completition: @escaping ResultCallback<T>) {
        
        guard let endpoint = endpoint as? MockEndpoint else {
            OperationQueue.main.addOperation({ completition(.failure(NetworkStackError.endpointNotMocked)) })
            return
        }
        
        guard let data = endpoint.mockData() else {
            OperationQueue.main.addOperation({ completition(.failure(NetworkStackError.mockDataMissing)) })
            return
        }
        
        parser.json(data: data, completition: completition)
    }
}

// Network Activity

enum NetworkActivityState {
    case show
    case hide
}

protocol NetworkActivityProtocol {
    func increment()
    func decrement()
    func observe(using closure: @escaping (NetworkActivityState) -> Void)
}

class NetworkActivity: NetworkActivityProtocol {
    private var observations = [(NetworkActivityState) -> Void]()
    
    private var activityCount: Int = 0 {
        didSet {
            
            if (activityCount < 0) {
                activityCount = 0
            }
            
            if (oldValue > 0 && activityCount > 0) {
                return
            }
            
            stateDidChange()
        }
    }
    
    private func stateDidChange() {
        
        let state = activityCount > 0 ? NetworkActivityState.show : NetworkActivityState.hide
        observations.forEach { closure in
             OperationQueue.main.addOperation({ closure(state) })
        }
    }
    
    func increment() {
        self.activityCount += 1
    }
    
    func decrement() {
        self.activityCount -= 1
    }
    
    func observe(using closure: @escaping (NetworkActivityState) -> Void) {
        observations.append(closure)
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
            
        } catch let error {
            OperationQueue.main.addOperation { completition(.failure(.parserError(error: error))) }
        }
    }
}

// Endpoint

protocol Endpoint {
    var request: URLRequest? { get }
    var httpMethod: String { get }
    var httpHeaders: [String : String]? { get }
    var queryItems: [URLQueryItem]? { get }
    var scheme: String { get }
    var host: String { get }
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
            for (key, value) in httpHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        return request
    }
}

// Mock Endpoint

protocol MockEndpoint: Endpoint {
    var mockFilename: String? { get }
    var mockExtension: String? { get }
}


extension MockEndpoint {
    func mockData() -> Data? {
        guard let mockFileUrl = Bundle.main.url(forResource: mockFilename, withExtension: mockExtension),
            let mockData = try? Data(contentsOf: mockFileUrl) else {
                return nil
        }
        return mockData
    }
}

extension MockEndpoint {
    var mockExtension: String? {
        return "json"
    }
}

// Example

extension Endpoint {
    var scheme: String {
        return "https"
    }
    
    var host: String {
        return "jsonplaceholder.typicode.com"
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
            return request(forEndpoint: "/users")
        case .get(let userId):
            return request(forEndpoint: "/users/\(userId)")
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
        let headers: [String: String] = ["headerField" : "headerValue"]
        switch self {
        case .all, .get( _):
            return headers
        }
    }
}

// Mock UserEndpoint

extension UserEndpoint: MockEndpoint {
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

let networkActivity = NetworkActivity()
let webService = WebService(networkActivity: networkActivity)
let mockWebService = MockWebService()

networkActivity.observe { state in
    switch state {
    case .show:
        print("Network activity indicator: SHOW")
    case .hide:
        print("Network activity indicator: HIDE")
    }
}

webService.request(UserEndpoint.all) { (result: Result<[User], NetworkStackError>) in
    switch result {
    case .failure(let error):
        dump(error)
    case .success(let users):
        dump(users)
    }
}

webService.request(UserEndpoint.get(userId: 10)) { (result: Result<User, NetworkStackError>) in
    switch result {
    case .failure(let error):
        dump(error)
    case .success(let users):
        dump(users)
    }
}

mockWebService.request(UserEndpoint.get(userId: 10)) { (result: Result<User, NetworkStackError>) in
    switch result {
    case .failure(let error):
        dump(error)
    case .success(let users):
        dump(users)
    }
}

mockWebService.request(UserEndpoint.all) { (result: Result<[User], NetworkStackError>) in
    switch result {
    case .failure(let error):
        dump(error)
    case .success(let users):
        dump(users)
    }
}
