import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../service/razorpay_service.dart';
import '../../service/auth_service.dart';
import '../../service/api_config.dart';
import '../../common/theme_color.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';

class RazorpayPaymentScreen extends StatefulWidget {
  final String subscriptionId;
  final String razorpaySubscriptionId;
  final double amount;
  final String planName;
  final String courseName;

  const RazorpayPaymentScreen({
    super.key,
    required this.subscriptionId,
    required this.razorpaySubscriptionId,
    required this.amount,
    required this.planName,
    required this.courseName,
  });

  @override
  State<RazorpayPaymentScreen> createState() => _RazorpayPaymentScreenState();
}

class _RazorpayPaymentScreenState extends State<RazorpayPaymentScreen> {
  final RazorpayService _razorpayService = RazorpayService();
  final AuthService _authService = AuthService();
  bool isLoading = false;
  bool paymentInProgress = false;
  String? errorMessage;
  String? successMessage;

  @override
  void initState() {
    super.initState();
    _initializeRazorpay();
  }

  void _initializeRazorpay() {
    _razorpayService.initialize(
      onSuccess: _handlePaymentSuccess,
      onFailure: _handlePaymentFailure,
      onExternalWallet: _handleExternalWallet,
    );
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    debugPrint('Payment Successful:');
    debugPrint('Payment ID: ${response.paymentId}');
    debugPrint('Order ID: ${response.orderId}');
    debugPrint('Signature: ${response.signature}');
    
    setState(() {
      paymentInProgress = false;
    });

    // Verify payment with backend
    await _verifyPaymentWithBackend(
      response.paymentId!,
      response.signature ?? '',
    );
  }

  void _handlePaymentFailure(PaymentFailureResponse response) {
    debugPrint('Payment Failed: ${response.code} - ${response.message}');
    
    setState(() {
      paymentInProgress = false;
      errorMessage = _getErrorMessage(response.code, response.message);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message}'),
        backgroundColor: AppColors.errorRed,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  String _getErrorMessage(int? code, String? message) {
    if (code == 1) {
      return 'Payment was cancelled by user';
    } else if (code == 2) {
      return 'Network error occurred. Please check your internet connection.';
    } else if (code == 3) {
      return 'Payment failed due to technical issues. Please try again.';
    }
    return message ?? 'Payment failed. Please try again.';
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('External Wallet: ${response.walletName}');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Redirected to: ${response.walletName}'),
        backgroundColor: AppColors.primaryYellow,
      ),
    );
  }

  Future<void> _verifyPaymentWithBackend(
    String paymentId, 
    String signature,
  ) async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      String accessToken = await _authService.getAccessToken();

      if (accessToken.isEmpty) {
        _navigateToLogin();
        return;
      }

      final client = _createHttpClientWithCustomCert();

      try {
        final requestBody = {
          'razorpay_payment_id': paymentId,
          'razorpay_subscription_id': widget.razorpaySubscriptionId,
          'razorpay_signature': signature,
        };

        debugPrint('Payment verification request:');
        debugPrint('Payment ID: $paymentId');
        debugPrint('Subscription ID: ${widget.razorpaySubscriptionId}');
        debugPrint('Signature: $signature');

        Future<http.Response> makeRequest(String token) {
          return client.post(
            Uri.parse('${ApiConfig.currentBaseUrl}/api/subscriptions/verify_subscription_payment/'),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $token',
            },
            body: json.encode(requestBody),
          ).timeout(ApiConfig.requestTimeout);
        }

        var response = await makeRequest(accessToken);

        debugPrint('Payment verification response status: ${response.statusCode}');
        debugPrint('Payment verification response body: ${response.body}');

        if (response.statusCode == 401) {
          debugPrint('⚠️ Access token expired, trying refresh...');

          final newAccessToken = await _authService.refreshAccessToken();

          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            response = await makeRequest(newAccessToken);
            debugPrint('🔄 Retried with refreshed token: ${response.statusCode}');
          } else {
            debugPrint('❌ Token refresh failed');
            await _authService.logout();
            _navigateToLogin();
            return;
          }
        }

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          
          if (responseData['success'] == true) {
            setState(() {
              successMessage = responseData['message'] ?? 'Payment verified successfully!';
              isLoading = false;
            });

            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(successMessage!),
                backgroundColor: AppColors.successGreen,
                duration: const Duration(seconds: 3),
              ),
            );

            // Wait a bit then navigate back with success
            await Future.delayed(const Duration(seconds: 2));

            // Navigate back with success result
            if (mounted) {
              Navigator.of(context).pop(true);
            }
          } else {
            setState(() {
              errorMessage = responseData['message'] ?? 'Payment verification failed';
              isLoading = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage!),
                backgroundColor: AppColors.errorRed,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        } else {
          final errorData = json.decode(response.body);
          setState(() {
            errorMessage = errorData['message'] ?? 'Payment verification failed: ${response.statusCode}';
            isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage!),
              backgroundColor: AppColors.errorRed,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } finally {
        client.close();
      }
    } on SocketException catch (e) {
      debugPrint('Network error during verification: $e');
      setState(() {
        errorMessage = 'Network error. Please check your internet connection.';
        isLoading = false;
      });
    } on HttpException catch (e) {
      debugPrint('HTTP error during verification: $e');
      setState(() {
        errorMessage = 'Server error. Please try again later.';
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error verifying payment: $e');
      setState(() {
        errorMessage = 'Error verifying payment: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  void _initiatePayment() {
    setState(() {
      paymentInProgress = true;
      errorMessage = null;
      successMessage = null;
    });

    _razorpayService.openPaymentGateway(
      amount: widget.amount,
      subscriptionId: widget.razorpaySubscriptionId,
      description: '${widget.planName} - ${widget.courseName}',
    );
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  void dispose() {
    _razorpayService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textDark,
          ),
          onPressed: () {
            if (paymentInProgress) {
              // Show confirmation dialog if payment is in progress
              _showExitConfirmation();
            } else {
              Navigator.of(context).pop(false);
            }
          },
        ),
        title: const Text(
          'Payment',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryYellow,
                    AppColors.primaryYellowDark,
                  ],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.payment_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Secure Payment',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete your subscription payment',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Payment Details Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.receipt_rounded,
                                color: AppColors.primaryYellow,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Order Summary',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          _buildDetailRow('Plan', widget.planName),
                          _buildDetailRow('Course', widget.courseName),
                          _buildDetailRow('Subscription ID', 
                              '${widget.razorpaySubscriptionId.substring(0, 10)}...'),
                          
                          const Divider(height: 30),
                          
                          _buildDetailRow(
                            'Total Amount',
                            '₹${widget.amount.toStringAsFixed(0)}',
                            isAmount: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Payment Status
                    if (isLoading) _buildLoadingIndicator(),
                    if (errorMessage != null) _buildErrorCard(),
                    if (successMessage != null) _buildSuccessCard(),

                    const SizedBox(height: 20),

                    // Payment Methods Info
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryYellow.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primaryYellow.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.credit_card_rounded,
                                size: 18,
                                color: AppColors.primaryYellow,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Accepted Payment Methods',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildPaymentMethodChip('Credit Cards'),
                              _buildPaymentMethodChip('Debit Cards'),
                              _buildPaymentMethodChip('UPI'),
                              _buildPaymentMethodChip('Net Banking'),
                              _buildPaymentMethodChip('Wallet'),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Security Info
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.successGreen.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.security_rounded,
                            size: 18,
                            color: AppColors.successGreen,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your payment is secured with Razorpay. All transactions are encrypted and secure.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textGrey,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Payment Button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(
                    color: AppColors.grey200,
                    width: 1,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                          ),
                        ),
                        Text(
                          '₹${widget.amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: isLoading
                        ? _buildLoadingButton()
                        : ElevatedButton(
                            onPressed: paymentInProgress ? null : _initiatePayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryYellow,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                              shadowColor: AppColors.primaryYellow.withOpacity(0.3),
                            ),
                            child: paymentInProgress
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Processing...',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.payment_rounded, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Pay Now',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String title, String value, {bool isAmount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textGrey,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isAmount ? 18 : 14,
              fontWeight: isAmount ? FontWeight.bold : FontWeight.normal,
              color: isAmount ? AppColors.primaryYellow : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodChip(String method) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.grey200,
        ),
      ),
      child: Text(
        method,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.textGrey,
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryYellow.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryYellow,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Verifying payment...',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.errorRed.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.errorRed,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payment Failed',
                  style: TextStyle(
                    color: AppColors.errorRed,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  errorMessage!,
                  style: const TextStyle(
                    color: AppColors.errorRed,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.successGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.successGreen.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.successGreen,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payment Successful',
                  style: TextStyle(
                    color: AppColors.successGreen,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  successMessage!,
                  style: const TextStyle(
                    color: AppColors.successGreen,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingButton() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.primaryYellow.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 8),
          Text(
            'Verifying...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Payment?'),
        content: const Text('Payment is in progress. Are you sure you want to exit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(false);
            },
            child: const Text(
              'Exit',
              style: TextStyle(color: AppColors.errorRed),
            ),
          ),
        ],
      ),
    );
  }
}