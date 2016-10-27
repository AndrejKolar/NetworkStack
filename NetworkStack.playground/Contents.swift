//: Playground - noun: a place where people can play

import UIKit
import PlaygroundSupport

// Types
typealias Json = [String: Any]

enum Result<T> {
    case success(T)
    case error(Error?)
}

typealias ResultCallback<T> = (Result<T>) -> Void

// Webservice.swift

class Webservice {
    static let sharedInstance = Webservice()
    
    private var urlSession = URLSession()
    
    private var networkActivityCount: Int = 0 {
        didSet {
            UIApplication.shared.isNetworkActivityIndicatorVisible = (networkActivityCount > 0)
        }
    }
    
    init() {
        self.urlSession = URLSession(configuration: URLSessionConfiguration.default)
    }
    
    func request<T>(_ endpoint: Endpoint, completition: @escaping ResultCallback<T>) {
        incrementNetworkActivity()
        
        let task = urlSession.dataTask(with: endpoint.request) { [unowned self] (data, response, error) in
            
            self.decrementNetworkActivity()
            
            guard let data = data else {
                OperationQueue.main.addOperation({ completition(.error(error)) })
                return
            }
            
            self.parseJSON(data: data, endpoint: endpoint, completition: completition)
        }
        
        task.resume()
    }
    
    func mockRequest<T>(_ endpoint: Endpoint, completition: @escaping ResultCallback<T>) {
        guard let data = endpoint.mockData else {
            OperationQueue.main.addOperation({ completition(.error(SerializationError.invalid("No mock data", nil))) })
            return
        }
        
        parseJSON(data: data, endpoint: endpoint, completition: completition)
    }
    
    // Network activity
    
    private func incrementNetworkActivity() {
        OperationQueue.main.addOperation({ self.networkActivityCount += 1 })
    }
    
    private func decrementNetworkActivity() {
        OperationQueue.main.addOperation({ self.networkActivityCount -= 1 })
    }
    
    // Parse JSON
    
    private func parseJSON<T>(data: Data, endpoint: Endpoint, completition: @escaping ResultCallback<T>) {
        
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            
            guard let jsonArray = json as? [Json] else {
                OperationQueue.main.addOperation { completition(.error(SerializationError.invalid("Not a JSON array", nil))) }
                return
            }
            
            let results =  try endpoint.parse(jsonArray) as! T
            OperationQueue.main.addOperation { completition(.success(results)) }
            
        } catch let parseError {
            OperationQueue.main.addOperation { completition(.error(parseError)) }
        }
    }
    
}

// Endpoint.swift

protocol Seriazible {
    init?(json: [String: Any]) throws
}

enum SerializationError: Error {
    case missing(String)
    case invalid(String, Any?)
}

protocol Endpoint {
    var baseUrlString: String { get }
    var request: URLRequest { get }
    var httpMethod: String { get }
    var mockData: Data? { get }
    
    func parse(_ jsonArray: [Json]) throws -> Any
}

// Parse helper functions
extension Endpoint {
    func parseArray<A: Seriazible>(_ jsonArray: [Json]) throws -> [A] {
        var results: [A] = []
        for jsonDict in jsonArray {
            if let entity = try A(json: jsonDict) {
                results.append(entity)
            }
        }
        return results
    }
    
    func parseDictionary<A: Seriazible>(_ jsonDictionary: Json) throws -> A {
        if let entity = try A(json: jsonDictionary) {
            return entity
        } else {
            throw SerializationError.invalid("Invalid json dictionary", jsonDictionary)
        }
    }
}

// UserEndpoint.swift

enum UserEndpoint {
    case all
}

extension UserEndpoint: Endpoint {
    var baseUrlString: String { return "http://www.mocky.io/v2" }
    
    var request: URLRequest {
        switch self {
        case .all:
            var request = URLRequest(url: URL(string: baseUrlString + "/5810c7d93a0000710660982d")!)
            request.httpMethod = self.httpMethod
            return request
        }
    }
    
    var httpMethod: String {
        switch self {
        case .all:
            return "GET"
        }
    }
    
    var mockData: Data? {
        switch self {
        case .all:
            return "[{\"id\":2, \"username\": \"AndrejKolar2\", \"email\": \"andrej.kolar@clevertech.biz\"}]".data(using: String.Encoding.utf8)
        }
    }
    
    func parse(_ jsonArray: [Json]) throws -> Any {
        switch self {
        case .all:
            let userArray: [User] = try parseArray(jsonArray)
            return userArray
        }
    }
}

// User.swift

struct User: Seriazible {
    let id: Int
    let username: String
    let email: String
    
    init?(json: [String: Any]) throws {
        guard let id = json["id"] as? Int else {
            throw SerializationError.missing("id")
        }
        
        guard let username = json["username"] as? String else {
            throw SerializationError.missing("username")
        }
        
        guard let email = json["email"] as? String else {
            throw SerializationError.missing("email")
        }
        
        self.id  = id
        self.username = username
        self.email = email
    }
}

// Playground

PlaygroundPage.current.needsIndefiniteExecution = true

// Run

let webservice = Webservice.sharedInstance

webservice.request(UserEndpoint.all) { (result: Result<[User]>) in
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
