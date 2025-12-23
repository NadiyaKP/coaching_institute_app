import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:coaching_institute_app/service/api_config.dart';
import '../../common/theme_color.dart';
import '../../../service/http_interceptor.dart';

class DescriptivePracticeScreen extends StatefulWidget {
  final String chapterId;
  final String chapterName;
  final String accessToken;

  const DescriptivePracticeScreen({
    super.key,
    required this.chapterId,
    required this.chapterName,
    required this.accessToken,
  });

  @override
  State<DescriptivePracticeScreen> createState() => _DescriptivePracticeScreenState();
}

class _DescriptivePracticeScreenState extends State<DescriptivePracticeScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  
  List<dynamic> _questions = [];
  int _currentQuestionIndex = 0;
  int _totalQuestions = 0;

  @override
  void initState() {
    super.initState();
    _fetchDescriptiveQuestions();
  }

  Future<void> _fetchDescriptiveQuestions() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      String encodedId = Uri.encodeComponent(widget.chapterId);
      String apiUrl = '${ApiConfig.baseUrl}/api/test/desc-questions/practice/?chapter_id=$encodedId';
      
      debugPrint('Fetching descriptive questions from: $apiUrl');
      debugPrint('Using access token: ${widget.accessToken.substring(0, 20)}...');
      
      final response = await globalHttpClient.get(
        Uri.parse(apiUrl),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer ${widget.accessToken}',
        },
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('Response Status Code: ${response.statusCode}');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['success'] == true) {
          final List<dynamic> questions = responseData['questions'] ?? [];
          final int count = responseData['count'] ?? 0;
          
          setState(() {
            _questions = questions;
            _totalQuestions = count;
            _isLoading = false;
          });
          
          debugPrint('✅ Successfully loaded $count descriptive questions');
        } else {
          _handleError('Failed to load questions: ${responseData['message'] ?? 'Unknown error'}');
        }
      } else if (response.statusCode == 401) {
        _handleError('Session expired. Please login again.');
      } else if (response.statusCode == 404) {
        _handleError('No descriptive questions available for this chapter.');
      } else {
        _handleError('Failed to load questions: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Exception occurred while fetching descriptive questions: $e');
      _handleError('Error loading questions: $e');
    }
  }

  void _handleError(String message) {
    setState(() {
      _isLoading = false;
      _hasError = true;
      _errorMessage = message;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.errorRed,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _navigateBack() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _nextQuestion() {
    if (_currentQuestionIndex < _totalQuestions - 1) {
      setState(() {
        _currentQuestionIndex++;
      });
    } else {
      _finishPractice();
    }
  }

  void _previousQuestion() {
    if (_currentQuestionIndex > 0) {
      setState(() {
        _currentQuestionIndex--;
      });
    }
  }

  void _finishPractice() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: AppColors.primaryYellow,
          ),
          const SizedBox(height: 20),
          Text(
            'Loading descriptive questions...',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.primaryBlue.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 60,
              color: AppColors.errorRed.withOpacity(0.7),
            ),
            const SizedBox(height: 20),
            const Text(
              'Failed to Load Questions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.errorRed,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _navigateBack,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Go Back',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 60,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 20),
            const Text(
              'No Descriptive Questions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'There are no descriptive questions available for ${widget.chapterName} at the moment.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _navigateBack,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Go Back',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard() {
    if (_questions.isEmpty || _currentQuestionIndex >= _questions.length) {
      return _buildEmptyScreen();
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final questionId = currentQuestion['id'] ?? '';
    final questionText = currentQuestion['question'] ?? 'No question text';
    final mark = currentQuestion['mark'] ?? 0;
    final List<dynamic> attachments = currentQuestion['attachments'] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryYellow,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Q${_currentQuestionIndex + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${mark} Marks',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  questionText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // Attachments Section
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.image,
                        color: AppColors.primaryYellow,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Attachments (${attachments.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: attachments.length,
                    itemBuilder: (context, index) {
                      final attachment = attachments[index];
                      final imageUrl = attachment['url'] ?? '';
                      
                      return GestureDetector(
                        onTap: () {
                          _showImageFullScreen(imageUrl);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  void _showImageFullScreen(String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height * 0.7,
                      color: Colors.grey[200],
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height * 0.7,
                      color: Colors.grey[200],
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image,
                              size: 50,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Failed to load image',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _showExitDialog() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warningOrange, size: 20),
              SizedBox(width: 12),
              Text(
                'Exit Practice?',
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to exit descriptive practice?',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[700], fontSize: 14),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Exit',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (bool didPop) async {
        if (!didPop) {
          bool? shouldExit = await _showExitDialog();
          if (shouldExit == true && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isLoading
                ? 'Loading...'
                : _questions.isEmpty
                    ? 'Descriptive Practice'
                    : 'Question ${_currentQuestionIndex + 1}/$_totalQuestions',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          backgroundColor: AppColors.primaryYellow,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () async {
              bool? shouldExit = await _showExitDialog();
              if (shouldExit == true && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primaryYellow,
                AppColors.backgroundLight,
                Colors.white,
              ],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
          child: _isLoading
              ? _buildLoadingScreen()
              : _hasError
                  ? _buildErrorScreen()
                  : _questions.isEmpty
                      ? _buildEmptyScreen()
                      : Column(
                          children: [
                            // Progress indicator
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              color: Colors.white.withOpacity(0.9),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Progress',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.primaryBlue,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        '${_currentQuestionIndex + 1}/$_totalQuestions',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.primaryBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(
                                    value: (_currentQuestionIndex + 1) / _totalQuestions,
                                    backgroundColor: Colors.grey[200],
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
                                    minHeight: 6,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ],
                              ),
                            ),

                            // Question content
                            Expanded(
                              child: _buildQuestionCard(),
                            ),

                            // Navigation buttons
                            SafeArea(
                              top: false,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                                margin: EdgeInsets.only(
                                  bottom: MediaQuery.of(context).viewInsets.bottom > 0
                                      ? MediaQuery.of(context).viewInsets.bottom
                                      : 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 12,
                                      offset: const Offset(0, -4),
                                    ),
                                  ],
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(20),
                                    topRight: Radius.circular(20),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Previous Button
                                    Expanded(
                                      child: Opacity(
                                        opacity: _currentQuestionIndex == 0 ? 0.5 : 1.0,
                                        child: ElevatedButton(
                                          onPressed: _currentQuestionIndex == 0 ? null : _previousQuestion,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primaryBlue,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            elevation: 4,
                                          ),
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.arrow_back,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Previous',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Next/Finish Button
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: _nextQuestion,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primaryYellow,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: 4,
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              _currentQuestionIndex == _totalQuestions - 1
                                                  ? 'Finish'
                                                  : 'Next',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              _currentQuestionIndex == _totalQuestions - 1
                                                  ? Icons.done_all
                                                  : Icons.arrow_forward,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
        ),
      ),
    );
  }
}