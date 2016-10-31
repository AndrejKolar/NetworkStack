/*: Description
# NetworkStack
Clean and simple networking stack
*/
import UIKit
import PlaygroundSupport

// Types
typealias Json = [String: Any]

protocol Serializable {
    init?(json: [String: Any]) throws
}

enum Result<T: Serializable> {
    case success([T])
    case error(Error?)
}

enum NetworkStackError: Error {
    case missing(String)
    case invalid(String, Any?)
}

typealias ResultCallback<T: Serializable> = (Result<T>) -> Void

// Webservice

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
            
            Parser.json(data: data, endpoint: endpoint, completition: completition)
        }
        
        task.resume()
    }
    
    func mockRequest<T>(_ endpoint: Endpoint, completition: @escaping ResultCallback<T>) {
        guard let data = endpoint.mockData else {
            OperationQueue.main.addOperation({ completition(.error(NetworkStackError.invalid("No mock data", nil))) })
            return
        }
        
        Parser.json(data: data, endpoint: endpoint, completition: completition)
    }
    
    // Network activity
    
    private func incrementNetworkActivity() {
        OperationQueue.main.addOperation({ self.networkActivityCount += 1 })
    }
    
    private func decrementNetworkActivity() {
        OperationQueue.main.addOperation({ self.networkActivityCount -= 1 })
    }
}

// Parser

class Parser {
    class func json<T>(data: Data, endpoint: Endpoint, completition: @escaping ResultCallback<T>) {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            
            if let jsonArray = json as? [Json] {
                let results: [T] = try parseArray(jsonArray)
                OperationQueue.main.addOperation { completition(.success(results)) }
            } else if let jsonDict = json as? Json {
                let result: T = try parseDictionary(jsonDict)
                OperationQueue.main.addOperation { completition(.success([result])) }
            } else {
                OperationQueue.main.addOperation { completition(.error(NetworkStackError.invalid("Not a JSON array", nil))) }
            }
        } catch let parseError {
            OperationQueue.main.addOperation { completition(.error(parseError)) }
        }
    }
    
    private class func parseArray<T: Serializable>(_ jsonArray: [Json]) throws -> [T] {
        var results: [T] = []
        for jsonDict in jsonArray {
            if let entity = try T(json: jsonDict) {
                results.append(entity)
            }
        }
        return results
    }
    
    private class func parseDictionary<T: Serializable>(_ jsonDict: Json) throws -> T {
        if let entity = try T(json: jsonDict) {
            return entity
        }
        
        throw NetworkStackError.missing("Cannot create entity from dictionary")
    }
}

// Endpoint

protocol Endpoint {
    var baseUrlString: String { get }
    var request: URLRequest { get }
    var httpMethod: String { get }
    var mockData: Data? { get }
}

// UserEndpoint

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
}

// User

struct User: Serializable {
    let id: Int
    let username: String
    let email: String
    
    init(json: [String: Any]) throws {
        guard let id = json["id"] as? Int else {
            throw NetworkStackError.missing("id")
        }
        
        guard let username = json["username"] as? String else {
            throw NetworkStackError.missing("username")
        }
        
        guard let email = json["email"] as? String else {
            throw NetworkStackError.missing("email")
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

webservice.request(UserEndpoint.all) { (result: Result<User>) in
    switch result {
    case .error(let error):
        dump(error)
    case .success(let users):
        dump(users)
    }
}

webservice.mockRequest(UserEndpoint.all) { (result: Result<User>) in
    switch result {
    case .error(let error):
        dump(error)
    case .success(let users):
        dump(users)
    }
}
