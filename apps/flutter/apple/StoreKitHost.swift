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
    if call.method == "purchasePromotionalOffer" {
      purchasePromotionalOffer(call.arguments, result: result)
      return
    }
    guard ["currentEntitlements", "latestSubscriptionTransaction"].contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard call.arguments == nil else {
      result(FlutterError(code: "invalid_arguments", message: "No arguments are expected.", details: nil))
      return
    }

    Task { @MainActor in
      if call.method == "latestSubscriptionTransaction" {
        var latest: StoreKit.Transaction?
        var proof: String?
        for productID in ["pomodoist.pro.monthly", "pomodoist.pro.annual"] {
          guard let verification = await StoreKit.Transaction.latest(for: productID) else { continue }
          guard case .verified(let transaction) = verification else {
            result(FlutterError(code: "storekit_unverified_transaction",
              message: "StoreKit could not verify subscription history.", details: nil))
            return
          }
          if latest == nil || transaction.purchaseDate > latest!.purchaseDate {
            latest = transaction
            proof = verification.jwsRepresentation
          }
        }
        if let transaction = latest, let jws = proof {
          result([
            "productId": transaction.productID,
            "transactionId": String(transaction.id),
            "jws": jws,
            "localVerificationData": String(decoding: transaction.jsonRepresentation, as: UTF8.self),
          ])
        } else {
          result(nil)
        }
        return
      }
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

  private func purchasePromotionalOffer(_ arguments: Any?, result: @escaping FlutterResult) {
    let offers = ["pomodoist.pro.monthly": "return_monthly_2026_v1",
                  "pomodoist.pro.annual": "return_annual_2026_v1"]
    guard let args = arguments as? [String: Any],
          let productID = args["productId"] as? String,
          let offerID = args["offerId"] as? String, offers[productID] == offerID,
          let jws = args["compactJws"] as? String, jws.utf8.count <= 32768,
          jws.split(separator: ".").count == 3 else {
      result(FlutterError(code: "invalid_arguments", message: "Invalid promotional purchase.", details: nil))
      return
    }
    var accountToken: UUID?
    if let token = args["appAccountToken"] {
      guard let value = token as? String, let uuid = UUID(uuidString: value) else {
        result(FlutterError(code: "invalid_arguments", message: "Invalid account token.", details: nil))
        return
      }
      accountToken = uuid
    }
    Task { @MainActor in
      do {
        guard let product = try await Product.products(for: [productID]).first,
              product.subscription?.promotionalOffers.contains(where: { $0.id == offerID }) == true else {
          result(FlutterError(code: "offer_unavailable", message: "The return offer is unavailable.", details: nil))
          return
        }
        for await verification in StoreKit.Transaction.unfinished {
          guard case .verified(let transaction) = verification else {
            result(FlutterError(code: "storekit_unverified_transaction", message: "StoreKit could not verify pending purchases.", details: nil))
            return
          }
          if transaction.productID == productID {
            result(FlutterError(code: "offer_pending", message: "A purchase is still pending.", details: nil))
            return
          }
        }
        // Xcode 26 back-deploys this identity-bound JWS option to iOS 15/macOS 12.
        // The installed Flutter plugin only supports the older, unbound signature.
        var options = Set(Product.PurchaseOption.promotionalOffer(offerID, compactJWS: jws))
        if let token = accountToken { options.insert(.appAccountToken(token)) }
        switch try await product.purchase(options: options) {
        case .success(let verification):
          guard case .verified(let transaction) = verification,
                transaction.productID == productID else {
            result(FlutterError(code: "storekit_unverified_transaction", message: "StoreKit could not verify the purchase.", details: nil))
            return
          }
          // Finish through the existing plugin only after the controller verifies entitlements.
          result([
            "status": "purchased",
            "productId": transaction.productID,
            "transactionId": String(transaction.id),
            "jws": verification.jwsRepresentation,
            "localVerificationData": String(decoding: transaction.jsonRepresentation, as: UTF8.self),
          ])
        case .pending:
          result(["status": "pending"])
        case .userCancelled:
          result(FlutterError(code: "userCancelled", message: "Purchase cancelled.", details: nil))
        @unknown default:
          result(FlutterError(code: "offer_unavailable", message: "Unknown purchase result.", details: nil))
        }
      } catch {
        let nativeError = error as NSError
        result(FlutterError(code: "promotional_purchase_failed", message: "StoreKit could not complete the return offer.",
          details: ["domain": nativeError.domain, "code": nativeError.code]))
      }
    }
  }

}
