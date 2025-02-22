//
//  Copyright © 2020 Iterable. All rights reserved.
//

import Foundation

struct RequestProcessorUtil {
    @discardableResult
    static func sendRequest(requestProvider: @escaping () -> Pending<SendRequestValue, SendRequestError>,
                            successHandler onSuccess: OnSuccessHandler? = nil,
                            failureHandler onFailure: OnFailureHandler? = nil,
                            authManager: IterableAuthManagerProtocol? = nil,
                            requestIdentifier identifier: String) -> Pending<SendRequestValue, SendRequestError> {
        let result = Fulfill<SendRequestValue, SendRequestError>()
        requestProvider().onSuccess { json in
            reportSuccess(result: result, value: json, successHandler: onSuccess, identifier: identifier)
        }
        .onError { error in
            if error.httpStatusCode == 401, error.iterableCode == JsonValue.Code.invalidJwtPayload {
                ITBError("invalid JWT token, trying again: \(error.reason ?? "")")
                authManager?.requestNewAuthToken(hasFailedPriorAuth: true) { _ in
                    requestProvider().onSuccess { json in
                        reportSuccess(result: result, value: json, successHandler: onSuccess, identifier: identifier)
                    }.onError { error in
                        reportFailure(result: result, error: error, failureHandler: onFailure, identifier: identifier)
                    }
                }
            } else if error.httpStatusCode == 401, error.iterableCode == JsonValue.Code.badApiKey {
                ITBError(error.reason)
                reportFailure(result: result, error: error, failureHandler: onFailure, identifier: identifier)
            } else {
                ITBError(error.reason)
                reportFailure(result: result, error: error, failureHandler: onFailure, identifier: identifier)
            }
        }
        return result
    }

    @discardableResult
    static func apply(successHandler onSuccess: OnSuccessHandler? = nil,
                      andFailureHandler onFailure: OnFailureHandler? = nil,
                      andAuthManager authManager: IterableAuthManagerProtocol? = nil,
                      toResult result: Pending<SendRequestValue, SendRequestError>,
                      withIdentifier identifier: String) -> Pending<SendRequestValue, SendRequestError> {
        result.onSuccess { json in
            if let onSuccess = onSuccess {
                onSuccess(json)
            } else {
                defaultOnSuccess(identifier)(json)
            }
        }.onError { error in
            if error.httpStatusCode == 401, error.iterableCode == JsonValue.Code.invalidJwtPayload {
                ITBError(error.reason)
                authManager?.requestNewAuthToken(hasFailedPriorAuth: true, onSuccess: nil)
            } else if error.httpStatusCode == 401, error.iterableCode == JsonValue.Code.badApiKey {
                ITBError(error.reason)
            }
            
            if let onFailure = onFailure {
                onFailure(error.reason, error.data)
            } else {
                defaultOnFailure(identifier)(error.reason, error.data)
            }
        }
        return result
    }
    
    private static func reportSuccess(result: Fulfill<SendRequestValue, SendRequestError>,
                                      value: SendRequestValue,
                                      successHandler onSuccess: OnSuccessHandler?,
                                      identifier: String) {
        if let onSuccess = onSuccess {
            onSuccess(value)
        } else {
            Self.defaultOnSuccess(identifier)(value)
        }
        result.resolve(with: value)
    }

    private static func reportFailure(result: Fulfill<SendRequestValue, SendRequestError>,
                                      error: SendRequestError,
                                      failureHandler onFailure: OnFailureHandler?,
                                      identifier: String) {
        
        if let onFailure = onFailure {
            onFailure(error.reason, error.data)
        } else {
            defaultOnFailure(identifier)(error.reason, error.data)
        }
        result.reject(with: error)
    }

    private static func defaultOnSuccess(_ identifier: String) -> OnSuccessHandler {
        { data in
            if let data = data {
                ITBInfo("\(identifier) succeeded, got response: \(data)")
            } else {
                ITBInfo("\(identifier) succeeded.")
            }
        }
    }
    
    private static func defaultOnFailure(_ identifier: String) -> OnFailureHandler {
        { reason, data in
            var toLog = "\(identifier) failed:"
            if let reason = reason {
                toLog += ", \(reason)"
            }
            if let data = data {
                toLog += ", got response \(String(data: data, encoding: .utf8) ?? "nil")"
            }
            ITBError(toLog)
        }
    }
}
