# NetworkStack
Clean &amp; simple Swift networking stack

##About
Example playground of a full network client written in Swift without any external dependancies. Base code is under 200 LOC.
The idea was to create something extendable and maintainable that can be used to quickly create a network layer with minimal boilerplate.
It was inspired by [Moya](https://github.com/Moya/Moya) just uses `URLSession` where Moya depends on `Alamofire`

##Features
- json parsing
- mocking responses
- error handeling
- auto on/off network activity indicator

##Classes

###Webservice 
Singleton instance for creating normal requests and mock requests. 
Also handles network activity indicator and makes sure the response is returned on the main thread (after parsing).

```swift
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
            
            Parser.json(data: data, completition: completition)
        }
        
        task.resume()
    }
    
    func mockRequest<T>(_ endpoint: Endpoint, completition: @escaping ResultCallback<T>) {
        guard let data = endpoint.mockData else {
            OperationQueue.main.addOperation({ completition(.error(NetworkStackError.invalid("No mock data", nil))) })
            return
        }
        
        Parser.json(data: data, completition: completition)
    }
    
    private func incrementNetworkActivity() {
        OperationQueue.main.addOperation({ self.networkActivityCount += 1 })
    }
    
    private func decrementNetworkActivity() {
        OperationQueue.main.addOperation({ self.networkActivityCount -= 1 })
    }
}
```

###Parser
Called from the `Webservice`, parses the json `Data` and and calls the result callback. Works for Array and Dictionary root json objects.

```swift
class Parser {
    class func json<T>(data: Data, completition: @escaping ResultCallback<T>) {
        
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            
            dump(json)
            
            if let jsonArray = json as? [Json] {
                let results: [T] = try parseArray(jsonArray)
                OperationQueue.main.addOperation { completition(.success(results)) }
            } else if let jsonDict = json as? Json {
                let result: T = try parseDictionary(jsonDict)
                OperationQueue.main.addOperation { completition(.success([result])) }
            } else {
                OperationQueue.main.addOperation { completition(.error(NetworkStackError.invalid("Not a JSON array", json))) }
            }
        } catch let parseError {
            dump(parseError)
            
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
        
        throw NetworkStackError.invalid("Cannot create entity from dictionary", jsonDict)
    }
}
```

###Endpoint
Base protocol that specific endpoint enums implement. An endpoint enum is passed to the Webservice when creating a request.

```swift
protocol Endpoint {
    var baseUrl: URL { get }
    var request: URLRequest { get }
    var httpMethod: String { get }
    var mockData: Data? { get }
    var queryItems: [URLQueryItem]? { get }
}

extension Endpoint {
    internal func requestForEndpoint(_ endpoint: String) -> URLRequest {
        let url = URL(string: endpoint, relativeTo: baseUrl)!
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        urlComponents.queryItems = self.queryItems
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = self.httpMethod
        return request
    }
}
```

###UserEndpoint
Example implementation of the Endpoint protocol. Implements two methods: `.all` for fetching all users and `.get(userId)`
 for fetching a specific user.
 
 ```swift
 enum UserEndpoint {
    case all
    case get(userId: Int)
}

extension UserEndpoint: Endpoint {
    var baseUrl: URL { return URL(string: "http://www.mocky.io")! }
    
    var request: URLRequest {
        switch self {
        case .all:
            return requestForEndpoint("/v2/58177efc1000008c01cc7fc2")
        case .get(_):
            return requestForEndpoint("/v2/58177ddc1000008901cc7fbf")
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
    
    var mockData: Data? {
        switch self {
        case .all:
            return "[{\"id\":2, \"username\": \"AndrejKolar2\", \"email\": \"andrej.kolar@clevertech.biz\"}]".data(using: String.Encoding.utf8)
        case .get( _):
            return "{\"id\":3, \"username\": \"AndrejKolar_Dict\", \"email\": \"andrej.kolar@clevertech.biz\"}".data(using: String.Encoding.utf8)
        }
    }
}
 ```
 
###User
Example of the entity model that the parser creates from the `Data` json.
Implements the `Serializable` protocol that has the constructor with the json param.

```swift
struct User: Serializable {
    let id: Int
    let username: String
    let email: String
    
    init(json: Json) throws {
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
``
 
##Example
Fetch a Webservice intance and create 2 normal request and one mock request.

```swift
let webservice = Webservice.sharedInstance

webservice.request(UserEndpoint.all) { (result: Result<User>) in
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
```
