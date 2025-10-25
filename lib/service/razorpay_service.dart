import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter/material.dart';
import '../service/razorpay_config.dart';

class RazorpayService {
  late Razorpay _razorpay;
  Function(PaymentSuccessResponse)? onSuccess;
  Function(PaymentFailureResponse)? onFailure;
  Function(ExternalWalletResponse)? onExternalWallet;

  void initialize({
    required Function(PaymentSuccessResponse) onSuccess,
    required Function(PaymentFailureResponse) onFailure,
    required Function(ExternalWalletResponse) onExternalWallet,
  }) {
    this.onSuccess = onSuccess;
    this.onFailure = onFailure;
    this.onExternalWallet = onExternalWallet;

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    debugPrint('=== Razorpay Payment Success ===');
    debugPrint('Payment ID: ${response.paymentId}');
    debugPrint('Order ID: ${response.orderId}');
    debugPrint('Signature: ${response.signature}');
    if (onSuccess != null) {
      onSuccess!(response);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('=== Razorpay Payment Error ===');
    debugPrint('Error Code: ${response.code}');
    debugPrint('Error Message: ${response.message}');
    if (onFailure != null) {
      onFailure!(response);
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('=== Razorpay External Wallet ===');
    debugPrint('Wallet: ${response.walletName}');
    if (onExternalWallet != null) {
      onExternalWallet!(response);
    }
  }

  void openPaymentGateway({
    required double amount,
    required String subscriptionId,
    String? email,
    String? contact,
    String? description,
  }) {
    final options = {
      'key': RazorpayConfig.keyId,
      'amount': (amount * 100).toInt(), // Convert to paise
      'name': 'EduApp',
      'description': description ?? 'Course Subscription',
      'prefill': {
        'contact': contact ?? '',
        'email': email ?? '',
      },
      'notes': {
        'subscription_id': subscriptionId,
      },
      'theme': {
        'color': '#FFD700',
        'backdrop_color': '#FFFFFF',
        'hide_topbar': false
      }
    };

    debugPrint('=== Opening Razorpay Gateway ===');
    debugPrint('Amount: $amount');
    debugPrint('Subscription ID: $subscriptionId');
    debugPrint('Options: $options');

    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error opening Razorpay: $e');
      rethrow;
    }
  }

  void dispose() {
    if (_razorpay != null) {
      _razorpay.clear();
    }
  }
}