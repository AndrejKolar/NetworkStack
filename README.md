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

###Parser
Called from the `Webservice`, parses the json `Data` and and calls the result callback. Works for Array and Dictionary root json objects.

###Endpoint
Base protocol that specific endpoint enums implement. An endpoint enum is passed to the Webservice when creating a request.

###UserEndpoint
Example implementation of the Endpoint protocol. Implements two methods: `.all` for fetching all users and `.get(userId)`
 for fetching a specific user. 
 
###User
Example of the entity model that the parser creates from the `Data` json.
Implements the `Serializable` protocol that has the constructor with the json param. 
 
##Example
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
