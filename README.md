# NetworkStack [![Language](https://img.shields.io/badge/swift-5.0-brightgreen.svg)](http://swift.org)

Clean &amp; simple Swift networking stack

## About

Full network client is written in Swift without any external dependencies. The base code is around 200 LOC.
The idea was to create an extendable and maintainable client that can be used to quickly create a network layer with minimal boilerplate.
It was inspired by [Moya](https://github.com/Moya/Moya), it just uses `URLSession` where `Moya` depends on `Alamofire`

## Features

- `enum Result<T, Error>` response handling
- dependancy injection
- endpoint modeling with the `Endpoint` protocol
- JSON parsing
- auto on/off network activity indicator
- easy mocking and testing

## Base code

Base code for the `NetworkStack` implementation.

### Types

Base types used in the client. Typealias callback with the `Result` response and the custom errors thrown by the networking stack.

```swift

typealias ResultCallback<T> = (Result<T, NetworkStackError>) -> Void

enum NetworkStackError: Error {
    case invalidRequest
    case dataMissing
    case endpointNotMocked
    case mockDataMissing
    case responseError(error: Error)
    case parserError(error: Error)
}
```

### WebService

The `WebService` class is used for making web requests. It implements the `WebServiceProtocol` which allows easy dependency injection and testing. The request method takes an `Endpoint` enum and a `ResultCallback`. It automatically toggles the network activity indicator using the `NetworkActivty` service and parses the data response using the `Parser` service.

```swift
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
```

### MockWebService

The `MockWebService` implements the same `WebServiceProtocol`. It skips making the actual web request and returns JSON data directly from a `.json` file included with the project. It is useful for running tests or returning mocked responses until the backend endpoint is ready.

```swift
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
```

### Network Activity

Service that handles the network activity indicator

```swift
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
```

### Parser

Called from the `Webservice`, parses the `Data` response and calls the result callback with initialized data structs.

```swift
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
```

### Endpoint

The base protocol that defines the data for a specific endpoint. An enum that implements the `Endpoint` protocol is passed to the `WebService` when creating a request.

```swift
protocol Endpoint {
    var request: URLRequest? { get }
    var httpMethod: String { get }
    var httpHeaders: [String : String]? { get }
    var queryItems: [URLQueryItem]? { get }
    var scheme: String { get }
    var host: String { get }
}

```

The protocol extension defines the request method that is used for creating an `URLRequest` from the `Endpoint` enum.

```swift
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
```

The `MockEndpoint` protocol inherits the Endpoint protocol and defines the data required for returning mocked responses.

```swift
protocol MockEndpoint: Endpoint {
    var mockFilename: String? { get }
    var mockExtension: String? { get }
}
```

The first extension defines the `mockData` method that will load the `.json` file for that endpoint and return it as a `Data` object.

```swift
extension MockEndpoint {
    func mockData() -> Data? {
        guard let mockFileUrl = Bundle.main.url(forResource: mockFilename, withExtension: mockExtension),
            let mockData = try? Data(contentsOf: mockFileUrl) else {
                return nil
        }
        return mockData
    }
}

```

The second extension has the default values for the `mockExtension`.

```swift
extension MockEndpoint {
    var mockExtension: String? {
        return "json"
    }
}
```

## Example

An example implementation of a single endpoint for fetching user data with two methods.

### Shared values

To set shared values between all the endpoints extend the base `Endpoint` enum. In this example, we are setting the scheme and host for all endpoints.

```swift
extension Endpoint {
    var scheme: String {
        return "https"
    }

    var host: String {
        return "jsonplaceholder.typicode.com"
    }
}
```

### UserEndpoint

Create the `UserEndpoint` for describing the users' endpoint. The enum has one case for each endpoint method. `.all` fetches all users and `get(userId: Int)` is used to fetch a user with a specific id.

```swift
enum UserEndpoint {
    case all
    case get(userId: Int)
}
```

The extension of the `UserEndpoint` defines the values that will be used when converting the UserEndpoint enum case into a `URLRequest`. The `request` property defines the URL, we also define the `httpMethod`, `queryItems` and `httpHeaders`.

```swift
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
```

### User

Create a User struct that represents the model that will be created by the `Parser` service. It needs to conform to the Codable protocol.

```swift
struct User: Codable {
    let id: Int
    let username: String
    let email: String
}
```

### Use

Create a `WebService` object, call its request method and pass it an Endpoint enum. Its also needed to specify the type of the result callback so that the `Parser` service knows how to create the model structs.

```swift
let webService = WebService()

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
```

## Mocking

### Setup

Create two `.json` files with the responses we want to return and add them to the project. Also, extend the `UserEndpoint` with the `MockEndpoint` protocol and set the filenames for the JSON response files.

```swift
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
```

### Use

Create a `MockWebService` instance and call the request method exactly the same way as for a normal `WebService`.

```swift
let mockWebService = MockWebService()

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
```
