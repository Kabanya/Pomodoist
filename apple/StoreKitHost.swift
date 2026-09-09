import Foundation
import StoreKit
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

final class StoreKitHost: NSObject, FlutterPlugin {
  static let channelName = "pomodoist/storekit"

  static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
    let messenger = registrar.messenger
    #else
    let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    registrar.addMethodCallDelegate(StoreKitHost(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "currentEntitlements" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard call.arguments == nil else {
      result(FlutterError(code: "invalid_arguments", message: "No arguments are expected.", details: nil))
      return
    }

    Task { @MainActor in
      var entitlements: [[String: String]] = []
      for await verification in StoreKit.Transaction.currentEntitlements {
        switch verification {
        case .verified(let transaction):
          entitlements.append([
            "productId": transaction.productID,
            "transactionId": String(transaction.id),
            "jws": verification.jwsRepresentation,
            "localVerificationData": String(decoding: transaction.jsonRepresentation, as: UTF8.self),
          ])
        case .unverified(_, let error):
          let nativeError = error as NSError
          result(FlutterError(
            code: "storekit_unverified_transaction",
            message: "StoreKit could not verify current entitlements.",
            details: ["domain": nativeError.domain, "code": nativeError.code]
          ))
          return
        }
      }
      result(entitlements)
    }
  }
}
