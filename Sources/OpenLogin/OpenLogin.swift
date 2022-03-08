import UIKit
import AuthenticationServices
import SafariServices

/**
 Authentication using OpenLogin.
 */
@available(iOS 12.0, *)
public class OpenLogin: NSObject {
    
    private let initParams: OLInitParams
    
    /**
     OpenLogin  component for authenticating with web-based flow.

     ```
     OpenLogin(OLInitParams(clientId: clientId, network: .mainnet))
     ```

     - parameter params: Init params for your OpenLogin instance.

     - returns: OpenLogin component.
     */
    public init(_ params: OLInitParams) {
        self.initParams = params
    }
    
    /**
     OpenLogin component for authenticating with web-based flow.
     
     ```
     OpenLogin()
     ```
     
     Parameters are loaded from the file `OpenLogin.plist` in your bundle with the following content:
     
     ```
     <?xml version="1.0" encoding="UTF-8"?>
     <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
     <plist version="1.0">
         <dict>
             <key>ClientId</key>
             <string>{YOUR_CLIENT_ID}</string>
             <key>Network</key>
             <string>mainnet|testnet</string>
         </dict>
     </plist>
     ```
     
     - parameter bundle: Bundle to locate the `OpenLogin.plist` file. By default is the main bundle.
     
     - returns: OpenLogin component.
     - important: Calling this method without a valid `OpenLogin.plist` will crash your application.
     */
    public convenience init (_ bundle: Bundle = Bundle.main) {
        let values = plistValues(bundle)!
        self.init(OLInitParams(clientId: values.clientId, network: values.network))
    }
    
    /**
     Starts the WebAuth flow by modally presenting a ViewController in the top-most controller.

     ```
     OpenLogin()
         .login(provider: .GOOGLE) {
             switch $0 {
             case .success(let result):
                 print("""
                     Signed in successfully!
                         Private key: \(result.privKey)
                         User info:
                             Name: \(result.userInfo.name)
                             Profile image: \(result.userInfo.profileImage ?? "N/A")
                             Type of login: \(result.userInfo.typeOfLogin)
                     """)
             case .failure(let error):
                 print("Error: \(error)")
             }
         }
     ```

     Any on going WebAuth auth session will be automatically cancelled when starting a new one,
     and it's corresponding callback with be called with a failure result of `OpenLoginError.appCancelled`

     - parameter callback: Callback called with the result of the WebAuth flow.
     */
    public func login(_ loginParams: OLLoginParams, _ callback: @escaping (Result<OpenLoginState>) -> Void) {
        DispatchQueue.main.async { [self] in
            guard
                let bundleId = Bundle.main.bundleIdentifier,
                let redirectURL = URL(string: "\(bundleId)://auth")
            else { return callback(.failure(OpenLoginError.noBundleIdentifierFound)) }
            
            guard
                let url = try? OpenLogin.generateAuthSessionURL(redirectURL: redirectURL, initParams: initParams, loginParams: loginParams)
            else {
                return callback(.failure(OpenLoginError.unknownError))
            }
            
            let authSession = ASWebAuthenticationSession(
                url: url, callbackURLScheme: redirectURL.scheme) { callbackURL, authError in
                guard
                    authError == nil,
                    let callbackURL = callbackURL,
                    let callbackState = try? OpenLogin.decodeStateFromCallbackURL(callbackURL)
                else {
                    let authError = authError ?? OpenLoginError.unknownError
                    if case ASWebAuthenticationSessionError.canceledLogin = authError {
                        return callback(.failure(OpenLoginError.userCancelled))
                    } else {
                        return callback(.failure(authError))
                    }
                }
                callback(.success(callbackState))
            }
            
            if #available(iOS 13.0, *) {
                authSession.presentationContextProvider = self
            }
            
            if !authSession.start() {
                callback(.failure(OpenLoginError.unknownError))
            }
        }
    }
    
    static func generateAuthSessionURL(redirectURL: URL, initParams: OLInitParams, loginParams: OLLoginParams) throws -> URL {
        
        var overridenInitParams = initParams
        
        // Init params redirectUrl has to be overriden unless users have their own tricks
        if overridenInitParams.redirectUrl == nil {
            overridenInitParams.redirectUrl = redirectURL.absoluteString
        }
        
        let sdkUrlParams = SdkUrlParams(initParams: overridenInitParams, params: loginParams)
        
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting.insert(.sortedKeys)
        
        guard
            let data = try? jsonEncoder.encode(sdkUrlParams),
            // Using sorted keys to produce consistent results
            var components = URLComponents(string: initParams.sdkUrl.absoluteString)
        else {
            throw OpenLoginError.unknownError
        }
        
        components.path = "/login"
        components.fragment = data.toBase64URL()
        
        guard let url = components.url
        else {
            throw OpenLoginError.unknownError
        }
        
        return url
    }
    
    static func decodeStateFromCallbackURL(_ callbackURL: URL) throws -> OpenLoginState {
        guard
            let callbackFragment = callbackURL.fragment,
            let callbackData = Data.fromBase64URL(callbackFragment),
            let callbackState = try? JSONDecoder().decode(OpenLoginState.self, from: callbackData)
        else {
            throw OpenLoginError.unknownError
        }
        return callbackState
    }
    
}

@available(iOS 12.0, *)
extension OpenLogin: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let window = UIApplication.shared.windows.first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}