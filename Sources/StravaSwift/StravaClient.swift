//
//  StravaClient.swift
//  StravaSwift
//
//  Created by Matthew on 11/11/2015.
//  Updated for Alamofire 5 by ChatGPT on 16.02.2025
//

import AuthenticationServices
import Foundation
import Alamofire
import SwiftyJSON
import SafariServices

public class StravaClient: NSObject {
    
    public static let sharedInstance = StravaClient()
    
    private override init() {}
    private var config: StravaConfig?
    
    public typealias AuthorizationHandler = (Result<OAuthToken, Error>) -> ()
    private var currentAuthorizationHandler: AuthorizationHandler?
    private var authSession: NSObject?
    
    public var token: OAuthToken? { return config?.delegate.get() }
    
    internal var authParams: [String: Any] {
        return [
            "client_id"        : config?.clientId ?? 0,
            "redirect_uri"     : config?.redirectUri ?? "",
            "scope"            : (config?.scopes ?? []).map { $0.rawValue }.joined(separator: ","),
            "state"            : "ios",
            "approval_prompt"  : config?.forcePrompt ?? true ? "force" : "auto",
            "response_type"    : "code"
        ]
    }
    
    internal func tokenParams(_ code: String) -> [String: Any]  {
        return [
            "client_id"     : config?.clientId ?? 0,
            "client_secret" : config?.clientSecret ?? "",
            "code"          : code
        ]
    }
    
    internal func refreshParams(_ refreshToken: String) -> [String: Any]  {
        return [
            "client_id"     : config?.clientId ?? 0,
            "client_secret" : config?.clientSecret ?? "",
            "grant_type"    : "refresh_token",
            "refresh_token" : refreshToken
        ]
    }
}

public extension StravaClient {
    func initWithConfig(_ config: StravaConfig) -> StravaClient {
        self.config = config
        return self
    }
}

extension StravaClient: ASWebAuthenticationPresentationContextProviding {
    
    var currentWindow: UIWindow? {
        return UIApplication.shared.windows.first { $0.isKeyWindow }
    }
    var currentViewController: UIViewController? {
        return currentWindow?.rootViewController
    }
    
    public func authorize(result: @escaping AuthorizationHandler) {
        let appAuthorizationUrl = Router.appAuthorizationUrl
        if UIApplication.shared.canOpenURL(appAuthorizationUrl) {
            currentAuthorizationHandler = result
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(appAuthorizationUrl, options: [:])
            } else {
                UIApplication.shared.openURL(appAuthorizationUrl)
            }
        } else {
            if #available(iOS 12.0, *) {
                let webAuthenticationSession = ASWebAuthenticationSession(url: Router.webAuthorizationUrl,
                                                                          callbackURLScheme: config?.redirectUri.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
                                                                          completionHandler: { (url, error) in
                    if let url = url, error == nil {
                        self.handleAuthorizationRedirect(url, result: result)
                    } else if let error = error {
                        result(.failure(error))
                    }
                })
                authSession = webAuthenticationSession
                if #available(iOS 13.0, *) {
                    webAuthenticationSession.presentationContextProvider = self
                }
                webAuthenticationSession.start()
            } else {
                currentAuthorizationHandler = result
                UIApplication.shared.open(Router.webAuthorizationUrl, options: [:])
            }
        }
    }
    
    public func handleAuthorizationRedirect(_ url: URL) -> Bool {
        if let redirectUri = config?.redirectUri,
           url.absoluteString.starts(with: redirectUri),
           let params = url.getQueryParameters(),
           params["code"] != nil,
           params["scope"] != nil,
           params["state"] == "ios" {
            
            self.handleAuthorizationRedirect(url) { result in
                if let currentAuthorizationHandler = self.currentAuthorizationHandler {
                    currentAuthorizationHandler(result)
                    self.currentAuthorizationHandler = nil
                }
            }
            return true
        } else {
            return false
        }
    }
    
    private func handleAuthorizationRedirect(_ url: URL, result: @escaping AuthorizationHandler) {
        if let code = url.getQueryParameters()?["code"] {
            self.getAccessToken(code, result: result)
        } else {
            result(.failure(generateError(failureReason: "Invalid authorization code", response: nil)))
        }
    }
    
    private func getAccessToken(_ code: String, result: @escaping AuthorizationHandler) {
        do {
            try oauthRequest(Router.token(code: code))?
                .responseStrava { [weak self] (response: AFDataResponse<OAuthToken>) in
                    guard let self = self else { return }
                    if let token = response.value {
                        self.config?.delegate.set(token)
                        result(.success(token))
                    } else if let error = response.error {
                        result(.failure(error))
                    } else {
                        result(.failure(self.generateError(failureReason: "No valid token", response: nil)))
                    }
                }
        } catch let error {
            result(.failure(error))
        }
    }
    
    public func refreshAccessToken(_ refreshToken: String, result: @escaping AuthorizationHandler) {
        do {
            try oauthRequest(Router.refresh(refreshToken: refreshToken))?
                .responseStrava { [weak self] (response: AFDataResponse<OAuthToken>) in
                    guard let self = self else { return }
                    if let token = response.value {
                        self.config?.delegate.set(token)
                        result(.success(token))
                    } else if let error = response.error {
                        result(.failure(error))
                    } else {
                        result(.failure(self.generateError(failureReason: "No valid token", response: nil)))
                    }
                }
        } catch let error {
            result(.failure(error))
        }
    }
    
    // MARK: ASWebAuthenticationPresentationContextProviding
    
    @available(iOS 12.0, *)
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return currentWindow ?? ASPresentationAnchor()
    }
}

public extension StravaClient {
    
    func upload<T: StravaModel>(_ route: Router,
                                upload: UploadData,
                                result: @escaping ((T?) -> Void),
                                failure: @escaping (NSError) -> Void) {
        do {
            try oauthUpload(URLRequest: route.asURLRequest(), upload: upload) { (response: AFDataResponse<T>) in
                if let statusCode = response.response?.statusCode, (400..<500).contains(statusCode) {
                    failure(self.generateError(failureReason: "Strava API Error", response: response.response))
                } else {
                    result(response.value)
                }
            }
        } catch let error as NSError {
            failure(error)
        }
    }
    
    func request<T: StravaModel>(_ route: Router,
                                 result: @escaping ((T?) -> Void),
                                 failure: @escaping (NSError) -> Void) {
        do {
            try oauthRequest(route)?
                .responseStrava { (response: AFDataResponse<T>) in
                    if let statusCode = response.response?.statusCode, (400..<500).contains(statusCode) {
                        failure(self.generateError(failureReason: "Strava API Error", response: response.response))
                    } else {
                        result(response.value)
                    }
                }
        } catch let error as NSError {
            failure(error)
        }
    }
    
    func request<T: StravaModel>(_ route: Router,
                                 result: @escaping (([T]?) -> Void),
                                 failure: @escaping (NSError) -> Void) {
        do {
            try oauthRequest(route)?
                .responseStravaArray { (response: AFDataResponse<[T]>) in
                    if let statusCode = response.response?.statusCode, (400..<500).contains(statusCode) {
                        failure(self.generateError(failureReason: "Strava API Error", response: response.response))
                    } else {
                        result(response.value)
                    }
                }
        } catch let error as NSError {
            failure(error)
        }
    }
    
    func generateError(failureReason: String, response: HTTPURLResponse?) -> NSError {
        let errorDomain = "com.stravaswift.error"
        let userInfo = [NSLocalizedFailureReasonErrorKey: failureReason]
        let code = response?.statusCode ?? 0
        return NSError(domain: errorDomain, code: code, userInfo: userInfo)
    }
}

extension StravaClient {
    
    func isConfigured() -> Bool {
        return config != nil
    }
    
    func checkConfiguration() {
        if !isConfigured() {
            fatalError("Strava client is not configured")
        }
    }
    
    func oauthRequest(_ urlRequest: URLRequestConvertible) throws -> DataRequest? {
        checkConfiguration()
        return AF.request(urlRequest)
    }

    func oauthUpload<T: StravaModel>(URLRequest urlRequest: URLRequestConvertible,
                                     upload: UploadData,
                                     completion: @escaping (AFDataResponse<T>) -> Void) {
        checkConfiguration()
        guard let url = try? urlRequest.asURLRequest().url else { return }
        AF.upload(multipartFormData: { multipartFormData in
            multipartFormData.append(upload.file,
                                     withName: "file",
                                     fileName: "\(upload.name ?? "default").\(upload.dataType)",
                                     mimeType: "application/octet-stream")
            for (key, value) in upload.params {
                if let valueString = value as? String,
                   let data = valueString.data(using: .utf8) {
                    multipartFormData.append(data, withName: key)
                }
            }
        }, to: url)
        .responseStrava { (response: AFDataResponse<T>) in
            completion(response)
        }
    }
}

extension URL {
    func getQueryParameters() -> [String: String]? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }
        var params = [String: String]()
        for item in queryItems {
            params[item.name] = item.value
        }
        return params
    }
}