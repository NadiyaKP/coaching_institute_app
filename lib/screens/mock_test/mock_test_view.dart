import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:coaching_institute_app/service/api_config.dart';
import '../../common/theme_color.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../mock_test/mock_test_result.dart';
import 'dart:async';
import '../../common/loading_animations.dart';
import '../../screens/mock_test/mock_test_detail.dart';
import '../../screens/subscription/subscription.dart';
import '../../../service/http_interceptor.dart';

class MockTestViewScreen extends StatefulWidget {
  final String chapterId; 
  final String chapterName; 
  final String accessToken;
  final String practiceType;

  const MockTestViewScreen({
    super.key,
    required this.chapterId, 
    required this.chapterName, 
    required this.accessToken,
    required this.practiceType, 
  });

  @override
  State<MockTestViewScreen> createState() => _MockTestViewScreenState();
}

class _MockTestViewScreenState extends State<MockTestViewScreen> {
  bool _isLoading = false;
  bool _testStarted = false;
  bool _testCompleted = false;
  bool _isReattempt = false;
  bool _hasPreviousResult = false;
  bool _isLoadingResult = false;
  bool _noQuestionsAvailable = false;
  
  int _studentId = 0;
  String _chapter = ''; 
  int _totalQuestions = 0; 
  List<dynamic> _questions = [];
  
  int _currentQuestionIndex = 0;
  Map<String, int> _selectedAnswers = {}; 
  Map<String, int> _questionStartTimes = {}; 
  Map<String, int> _questionTimeTaken = {}; 
  Map<String, bool> _questionSkipped = {}; 
  
  late Box _mockTestBox;
  bool _hiveInitialized = false;

  // Skip button variables
  bool _isSkipHolding = false;
  double _skipProgress = 0.0;
  late Timer _skipTimer;
  int _skipClickCount = 0;
  Timer? _skipMessageTimer;

  @override
  void initState() {
    super.initState();
    _initializeHive();
  }

  @override
  void dispose() {
    _skipTimer.cancel();
    _skipMessageTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeHive() async {
    try {
      await Hive.initFlutter();
      _mockTestBox = await Hive.openBox('mockTestData');
      setState(() {
        _hiveInitialized = true;
      });
      
      await _checkPreviousResult();
      
    } catch (e) {
      debugPrint('Hive initialization error: $e');
    }
  }

  Future<void> _checkPreviousResult() async {
    if (!_hiveInitialized) return;
    
    try {
      final testData = _mockTestBox.get('${widget.chapterId}_test_data'); 
      if (testData != null) {
        final lastAttemptDate = testData['last_attempt_date'] ?? '';
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final hasApiResponse = testData['api_response'] != null;
        
        setState(() {
          _isReattempt = lastAttemptDate == today;
          _hasPreviousResult = hasApiResponse;
        });
        
        debugPrint('Reattempt status: $_isReattempt (Last attempt: $lastAttemptDate, Today: $today)');
        debugPrint('Has previous result: $_hasPreviousResult');
      }
    } catch (e) {
      debugPrint('Error checking previous result: $e');
    }
  }

  Future<void> _fetchMockTestQuestions() async {
    setState(() {
      _isLoading = true;
      _noQuestionsAvailable = false;
    });

    try {
    
      String encodedId = Uri.encodeComponent(widget.chapterId);
      String apiUrl = '${ApiConfig.baseUrl}/api/performance/mock-test/start/?chapter_id=$encodedId'; 
      
      debugPrint('Fetching mock test questions from: $apiUrl');
      debugPrint('Using access token: ${widget.accessToken.substring(0, 20)}...');
      
      final response = await  globalHttpClient.get(
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
        
        // Check if this is a FREE_USER_LIMIT error
        if (responseData['success'] == false && 
            responseData['error_code'] == 'FREE_USER_LIMIT') {
          setState(() {
            _isLoading = false;
          });
          
          // Show premium message with navigation option
          _showPremiumUpgradeDialog(
            responseData['message'] ?? 
            'Free users can attempt only one mock test. Upgrade to premium for unlimited attempts.'
          );
          return;
        }
        
        // Check if questions array exists and has questions
        final List<dynamic> questions = responseData['questions'] ?? [];
        
        if (questions.isEmpty) {
          setState(() {
            _isLoading = false;
            _noQuestionsAvailable = true;
          });
          return;
        }
        
        setState(() {
          _studentId = responseData['student_id'] ?? 0;
          _chapter = responseData['chapter'] ?? widget.chapterName;
          _questions = questions;
          _totalQuestions = questions.length; 
          _isLoading = false;
          _noQuestionsAvailable = false;
        });
        
        // Store complete test data in Hive for result screen
        await _storeTestData();
        
        debugPrint('✅ Mock test loaded successfully!');
        debugPrint('Total questions: $_totalQuestions');
        debugPrint('Student ID: $_studentId');
        
      } else if (response.statusCode == 401) {
        _handleError('Session expired. Please login again.');
        _navigateBack();
      } else if (response.statusCode == 404) {
        // Handle 404 - No questions available
        setState(() {
          _isLoading = false;
          _noQuestionsAvailable = true;
        });
        debugPrint('❌ No questions available for this chapter (404)');
      } else {
        // Try to parse error response
        try {
          final Map<String, dynamic> errorData = json.decode(response.body);
          if (errorData['error_code'] == 'FREE_USER_LIMIT') {
            setState(() {
              _isLoading = false;
            });
            
            _showPremiumUpgradeDialog(
              errorData['message'] ?? 
              'Free users can attempt only one mock test. Upgrade to premium for unlimited attempts.'
            );
            return;
          }
        } catch (e) {
          debugPrint('Error parsing error response: $e');
        }
        
        _handleError('Failed to load mock test: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Exception occurred while fetching mock test: $e');
      // Check if it's a 404 error in the exception
      if (e.toString().contains('404')) {
        setState(() {
          _isLoading = false;
          _noQuestionsAvailable = true;
        });
      } else {
        _handleError('Error loading mock test: $e');
      }
    }
  }

  void _showPremiumUpgradeDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.workspace_premium, color: AppColors.primaryYellow, size: 24),
               SizedBox(width: 12),
               Expanded(
                child: Text(
                  'Premium Feature',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primaryYellow.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Premium Benefits:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildBenefitItem('Unlimited mock test attempts'),
                    _buildBenefitItem('Detailed performance analytics'),
                    _buildBenefitItem('Access to all features'),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); 
              },
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[700], fontSize: 14),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); 
                Navigator.of(context).pop(); 
                // Navigate to subscription page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SubscriptionScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Upgrade to Premium',
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

  Widget _buildBenefitItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            size: 14,
            color: AppColors.primaryYellow,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _storeTestData() async {
    if (!_hiveInitialized) return;
    
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _mockTestBox.put('${widget.chapterId}_test_data', { 
        'last_attempt_date': today,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'student_id': _studentId,
        'chapter': _chapter, 
        'total_questions': _totalQuestions,
        'questions': _questions,
        'selected_answers': _selectedAnswers,
        'chapter_name': widget.chapterName, 
      });
      debugPrint('✅ Complete test data stored in Hive');
    } catch (e) {
      debugPrint('Error storing test data in Hive: $e');
    }
  }

  void _handleError(String message) {
    setState(() {
      _isLoading = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.errorRed,
          duration: const Duration(seconds: 4),
          action: message.toLowerCase().contains('upgrade') || 
                  message.toLowerCase().contains('premium')
              ? SnackBarAction(
                  label: 'Upgrade',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SubscriptionScreen(),
                      ),
                    );
                  },
                )
              : null,
        ),
      );
    }
  }

  void _navigateBack() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _startTest() async {
    setState(() {
      _isLoading = true;
      _noQuestionsAvailable = false;
    });
    
    // Fetch questions only when start button is clicked
    await _fetchMockTestQuestions();
    
    if (_noQuestionsAvailable) {
      _handleError('No questions available for this chapter.');
      return;
    }

    if (_questions.isEmpty) {
      _handleError('No questions available for this test.');
      return;
    }

    // Initialize timing data
    _questionStartTimes.clear();
    _questionTimeTaken.clear();
    _questionSkipped.clear();
    _selectedAnswers.clear();
    _currentQuestionIndex = 0;
    
    // Start timing for first question
    final firstQuestion = _questions[0];
    final firstQuestionId = firstQuestion['question_id'];
    _questionStartTimes[firstQuestionId] = DateTime.now().millisecondsSinceEpoch;
    
    setState(() {
      _testStarted = true;
      _isReattempt = false; // Reset reattempt flag once test starts
    });
  }

  void _recordQuestionTime(String questionId) {
    final endTime = DateTime.now().millisecondsSinceEpoch;
    final startTime = _questionStartTimes[questionId];
    
    if (startTime != null) {
      final timeTakenInSeconds = (endTime - startTime) ~/ 1000;
      _questionTimeTaken[questionId] = timeTakenInSeconds;
      debugPrint('Time taken for question $questionId: $timeTakenInSeconds seconds');
    }
  }

  void _selectAnswer(String questionId, int optionId) {
    _recordQuestionTime(questionId);
    
    setState(() {
      _selectedAnswers[questionId] = optionId;
      _questionSkipped[questionId] = false;
    });
    
    // Update Hive with current answers
    _updateHiveAnswers();
  }

  Future<void> _updateHiveAnswers() async {
    if (!_hiveInitialized) return;
    
    try {
      final existingData = _mockTestBox.get('${widget.chapterId}_test_data') ?? {}; 
      await _mockTestBox.put('${widget.chapterId}_test_data', { 
        ...existingData,
        'selected_answers': _selectedAnswers,
      });
    } catch (e) {
      debugPrint('Error updating Hive answers: $e');
    }
  }

  void _startSkipTimer() {
    setState(() {
      _isSkipHolding = true;
      _skipProgress = 0.0;
    });

    _skipTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      setState(() {
        _skipProgress += 0.05;
        
        if (_skipProgress >= 1.0) {
          timer.cancel();
          _skipQuestionConfirmed();
        }
      });
    });
  }

  void _cancelSkipTimer() {
    _skipTimer.cancel();
    setState(() {
      _isSkipHolding = false;
      _skipProgress = 0.0;
      _skipClickCount++;
    });

    // Show skip instruction message if user clicks multiple times without holding
    if (_skipClickCount >= 2 && _skipClickCount <= 3) {
      _showSkipInstruction();
    }
  }

  void _showSkipInstruction() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Hold the skip button to skip the question',
          style: TextStyle(fontSize: 14),
        ),
        backgroundColor: AppColors.warningOrange,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

    // Reset counter after 5 seconds
    _skipMessageTimer?.cancel();
    _skipMessageTimer = Timer(const Duration(seconds: 5), () {
      _skipClickCount = 0;
    });
  }

  void _skipQuestionConfirmed() {
    final currentQuestionId = _questions[_currentQuestionIndex]['question_id'];
    _recordQuestionTime(currentQuestionId);
    
    setState(() {
      // Remove any selected answer for this question and mark as skipped
      _selectedAnswers.remove(currentQuestionId);
      _questionSkipped[currentQuestionId] = true;
      _questionTimeTaken[currentQuestionId] = 0; 
      _isSkipHolding = false;
      _skipProgress = 0.0;
      _skipClickCount = 0;
    });

    if (_currentQuestionIndex < _questions.length - 1) {
      _moveToNextQuestion();
    } else {
      _showFinishDialog();
    }
  }

  void _moveToNextQuestion() {
    // Start timing for next question
    final nextQuestionIndex = _currentQuestionIndex + 1;
    if (nextQuestionIndex < _questions.length) {
      final nextQuestion = _questions[nextQuestionIndex];
      final nextQuestionId = nextQuestion['question_id'];
      _questionStartTimes[nextQuestionId] = DateTime.now().millisecondsSinceEpoch;
    }
    
    setState(() {
      _currentQuestionIndex = nextQuestionIndex;
    });
  }

  void _nextQuestion() {
    final currentQuestionId = _questions[_currentQuestionIndex]['question_id'];
    final isAnswered = _selectedAnswers.containsKey(currentQuestionId);
    
    // If current question is not answered, show snackbar instead of dialog
    if (!isAnswered) {
      _showAnswerRequiredSnackbar();
      return;
    }

    // If current question is answered, record the time
    if (isAnswered) {
      _recordQuestionTime(currentQuestionId);
    }

    if (_currentQuestionIndex < _questions.length - 1) {
      _moveToNextQuestion();
    } else {
      _showFinishDialog();
    }
  }

  void _showAnswerRequiredSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Please select an answer before proceeding to the next question.',
          style: TextStyle(fontSize: 14),
        ),
        backgroundColor: AppColors.errorRed,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _prepareAnswersData() {
    List<Map<String, dynamic>> answers = [];
    
    for (var question in _questions) {
      final questionId = question['question_id'];
      final selectedOption = _selectedAnswers[questionId];
      final timeTaken = _questionTimeTaken[questionId] ?? 0;
      final skipped = _questionSkipped[questionId] ?? (selectedOption == null);
      
      // Convert time from seconds to minutes with 1 decimal place
      final timeTakenInMinutes = timeTaken / 60.0;
      
      answers.add({
        "question_id": questionId,
        "selected_option": skipped ? 0 : (selectedOption ?? 0),
        "time_taken": double.parse(timeTakenInMinutes.toStringAsFixed(1)),
        "skipped": skipped,
      });
    }
    
    return answers;
  }

  Future<Map<String, dynamic>?> _submitTestResults() async {
    try {
      final answers = _prepareAnswersData();
      
      final requestBody = {
        "chapter_id": widget.chapterId,
        "answers": answers,
      };
      
      debugPrint('Submitting test results: ${json.encode(requestBody)}');
      
      final response = await  globalHttpClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/performance/mock-test/end/'),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer ${widget.accessToken}',
        },
        body: json.encode(requestBody),
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('Submission Response Status: ${response.statusCode}');
      debugPrint('Submission Response Body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('✅ Test results submitted successfully!');
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        // Store API response in Hive for result screen
        await _storeApiResponse(responseData);
        
        return responseData;
      } else if (response.statusCode == 401) {
        _handleError('Session expired. Please login again.');
        return null;
      } else {
        _handleError('Failed to submit test results: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error submitting test results: $e');
      _handleError('Error submitting test results. Please check your connection.');
      return null;
    }
  }

  Future<void> _storeApiResponse(Map<String, dynamic> responseData) async {
    if (!_hiveInitialized) return;
    
    try {
      final existingData = _mockTestBox.get('${widget.chapterId}_test_data') ?? {}; 
      await _mockTestBox.put('${widget.chapterId}_test_data', {
        ...existingData,
        'api_response': responseData,
      });
      debugPrint('✅ API response stored in Hive');
    } catch (e) {
      debugPrint('Error storing API response in Hive: $e');
    }
  }

  void _showFinishDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.assignment_turned_in, color: AppColors.primaryYellow, size: 20),
              SizedBox(width: 12),
              Text(
                'Submit Exam',
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have answered ${_selectedAnswers.length} out of $_totalQuestions questions.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Text(
                'Are you sure you want to submit your test?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[700], fontSize: 14),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _completeTest();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Submit',
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

  Future<void> _completeTest() async {
    // Record time for current question if any
    if (_testStarted && _currentQuestionIndex < _questions.length) {
      final currentQuestionId = _questions[_currentQuestionIndex]['question_id'];
      _recordQuestionTime(currentQuestionId);
    }
    
    setState(() {
      _isLoading = true;
    });
    
    // Submit test results to API and get response
    final resultData = await _submitTestResults();
    
    setState(() {
      _isLoading = false;
    });
    
    if (resultData != null && mounted) {
      // Navigate to result screen with the API response data and Hive data
      final hiveData = _mockTestBox.get('${widget.chapterId}_test_data') ?? {}; 
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MockTestResultScreen(
            resultData: resultData,
            chapterName: widget.chapterName, 
            totalQuestions: _totalQuestions,
            answeredQuestions: _selectedAnswers.length,
            questions: hiveData['questions'] ?? [],
            selectedAnswers: hiveData['selected_answers'] ?? {},
            onBackPressed: _clearHiveData,
          ),
        ),
      );
    } else if (mounted) {
      _handleError('Failed to get test results. Please try again.');
    }
  }

  Future<void> _clearHiveData() async {
    if (!_hiveInitialized) return;
    
    try {
      // Keep only the last attempt date, remove all other data
      final existingData = _mockTestBox.get('${widget.chapterId}_test_data') ?? {}; 
      final lastAttemptDate = existingData['last_attempt_date'];
      
      await _mockTestBox.put('${widget.chapterId}_test_data', { 
        'last_attempt_date': lastAttemptDate,
      });
      
      debugPrint('✅ Hive data cleared except last attempt date');
    } catch (e) {
      debugPrint('Error clearing Hive data: $e');
    }
  }

  Future<void> _viewPreviousResult() async {
    setState(() {
      _isLoading = true;
      _isLoadingResult = true;
    });

    try {
      final hiveData = _mockTestBox.get('${widget.chapterId}_test_data') ?? {};
      final lastAttemptDate = hiveData['last_attempt_date'];
      
      if (lastAttemptDate == null) {
        _handleError('No previous attempt found.');
        setState(() { 
          _isLoading = false;
          _isLoadingResult = false;
        });
        return;
      }

      // Encode the chapter ID instead of unit ID
      String encodedId = Uri.encodeComponent(widget.chapterId);
      String apiUrl = '${ApiConfig.baseUrl}/api/test/results/?chapter_id=$encodedId&date=$lastAttemptDate'; 
      
      debugPrint('Fetching detailed results from: $apiUrl');
      
      final response = await  globalHttpClient.get(
        Uri.parse(apiUrl),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer ${widget.accessToken}',
        },
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('Detailed Results Response Status: ${response.statusCode}');
      debugPrint('Detailed Results Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['success'] == false && 
            responseData['error_code'] == 'FREE_USER_LIMIT') {
          setState(() {
            _isLoading = false;
            _isLoadingResult = false;
          });
          
          _showPremiumUpgradeDialog(
            responseData['message'] ?? 
            'Free users can attempt only one mock test. Upgrade to premium for unlimited attempts.'
          );
          return;
        }
        
        if (responseData['success'] == true && mounted) {
          setState(() {
            _isLoading = false;
            _isLoadingResult = false;
          });
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MockTestResultDetailScreen(
                resultData: responseData,
                chapterName: widget.chapterName,
                attemptDate: lastAttemptDate,
              ),
            ),
          );
        } else {
          _handleError('Failed to load detailed results.');
          setState(() { 
            _isLoading = false;
            _isLoadingResult = false;
          });
        }
      } else {
        // Try to parse error response
        try {
          final Map<String, dynamic> errorData = json.decode(response.body);
          if (errorData['error_code'] == 'FREE_USER_LIMIT') {
            setState(() {
              _isLoading = false;
              _isLoadingResult = false;
            });
            
            _showPremiumUpgradeDialog(
              errorData['message'] ?? 
              'Free users can attempt only one mock test. Upgrade to premium for unlimited attempts.'
            );
            return;
          }
        } catch (e) {
          debugPrint('Error parsing error response: $e');
        }
        
        _handleError('Failed to load detailed results: ${response.statusCode}');
        setState(() { 
          _isLoading = false;
          _isLoadingResult = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching detailed results: $e');
      _handleError('Error loading detailed results. Please check your connection.');
      setState(() { 
        _isLoading = false;
        _isLoadingResult = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_testStarted,
      onPopInvoked: (bool didPop) async {
        if (!didPop && _testStarted) {
          bool? shouldExit = await _showExitDialog();
          if (shouldExit == true && mounted) {
            // Record time before exiting
            if (_currentQuestionIndex < _questions.length) {
              final currentQuestionId = _questions[_currentQuestionIndex]['question_id'];
              _recordQuestionTime(currentQuestionId);
            }
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _testStarted 
              ? 'Question ${_currentQuestionIndex + 1}/$_totalQuestions' 
              : widget.chapterName, 
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
              if (_testStarted) {
                bool? shouldExit = await _showExitDialog();
                if (shouldExit == true && mounted) {
                  // Record time before exiting
                  if (_currentQuestionIndex < _questions.length) {
                    final currentQuestionId = _questions[_currentQuestionIndex]['question_id'];
                    _recordQuestionTime(currentQuestionId);
                  }
                  Navigator.of(context).pop();
                }
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: _testStarted && !_testCompleted
              ? [
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: TextButton(
                      onPressed: _showFinishDialog,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        ),
                      ),
                      child: const Text(
                        'Finish Exam',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ]
              : null,
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
              ? _buildLoadingScreen(
                  _testStarted 
                    ? 'Evaluating your test...' 
                    : 'Preparing questions for you...'
                )
              : _noQuestionsAvailable
                  ? _buildNoQuestionsScreen()
                  : _testStarted
                      ? _buildTestScreen()
                      : _buildStartScreen(),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const StaggeredDotsWave(size: Size(80, 60)),
          const SizedBox(height: 20),
          Text(
            _isLoadingResult 
              ? 'Gathering your result...'
              : message,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoQuestionsScreen() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.quiz_outlined,
                size: 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 20),
              Text(
                'No Questions Available',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'There are no questions available for ${widget.chapterName} at the moment.',
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
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
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
      ),
    );
  }

  Widget _buildStartScreen() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _isReattempt ? Colors.grey[100] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryYellow.withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    _isReattempt ? Icons.refresh : Icons.assignment,
                    size: 60,
                    color: _isReattempt ? Colors.grey[600] : AppColors.primaryYellow,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.chapterName, 
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _isReattempt ? Colors.grey[700] : AppColors.primaryBlue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  
                  Divider(color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isReattempt ? Colors.grey[200] : AppColors.primaryYellow.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isReattempt ? Colors.grey[400]! : AppColors.primaryYellow.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isReattempt ? 'Re-attempt Instructions:' : 'Instructions:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _isReattempt ? Colors.grey[700] : AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isReattempt 
                            ? '• This is a re-attempt of today\'s test\n'
                              '• Your previous attempt will be replaced\n'
                              '• Questions may be different\n'
                              '• Complete all questions for best results'
                            : '• Select one option for each question\n'
                              '• You can skip questions by holding skip button\n'
                              '• You can review the answers after exam\n'
                              '• Click Finish when done\n'
                              '• Time taken for each question will be recorded',
                          style: TextStyle(
                            fontSize: 12,
                            color: _isReattempt ? Colors.grey[600] : Colors.black87,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            
            // Start/Re-attempt Test Button
            SizedBox(
              width: double.infinity,
              height: 44, 
              child: ElevatedButton(
                onPressed: _startTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isReattempt ? Colors.grey[600] : AppColors.primaryYellow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 6,
                  shadowColor: (_isReattempt ? Colors.grey : AppColors.primaryYellow).withOpacity(0.4),
                ),
                child: Text(
                  _isReattempt ? 'Re-attempt Test' : 'Start Test',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            
            // View Result Button (only show if there's a previous result)
            if (_hasPreviousResult) ...[
              const SizedBox(height: 12), 
              SizedBox(
                width: double.infinity,
                height: 44, 
                child: OutlinedButton(
                  onPressed: _viewPreviousResult,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(
                      color: AppColors.primaryBlue,
                      width: 2,
                    ),
                  ),
                  child: const Text(
                    'View Result',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTestScreen() {
    if (_questions.isEmpty) {
      return const Center(
        child: Text('No questions available'),
      );
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final questionId = currentQuestion['question_id'];
    final questionText = currentQuestion['question'] ?? 'No question text';
    final options = currentQuestion['options'] ?? [];
    final selectedAnswerId = _selectedAnswers[questionId];
    final isLastQuestion = _currentQuestionIndex == _questions.length - 1;

    return Column(
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
                    '${_selectedAnswers.length}/$_totalQuestions answered',
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
        
        // Question content - Made scrollable
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
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
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        questionText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryBlue,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Options - Made scrollable
                ...List.generate(options.length, (index) {
                  final option = options[index];
                  final optionId = option['id'];
                  final optionText = option['text'] ?? '';
                  final isSelected = selectedAnswerId == optionId;
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => _selectAnswer(questionId, optionId),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? AppColors.primaryYellow.withOpacity(0.1)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primaryYellow
                                : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primaryYellow.withOpacity(0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primaryYellow
                                    : Colors.grey[200],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primaryYellow
                                      : Colors.grey[400]!,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  String.fromCharCode(65 + index), // A, B, C, D
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.black54,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                optionText,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isSelected
                                      ? AppColors.primaryBlue
                                      : Colors.black87,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: AppColors.primaryYellow,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                
                // Add extra space at the bottom to ensure buttons are visible
                const SizedBox(height: 80), // Increased space for buttons
              ],
            ),
          ),
        ),
        
        // Navigation buttons - Lifted significantly upward with SafeArea
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), // Increased padding on all sides
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom > 0 
                  ? MediaQuery.of(context).viewInsets.bottom 
                  : 16, // Extra margin to avoid device buttons
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
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      GestureDetector(
                        onTapDown: (_) => _startSkipTimer(),
                        onTapUp: (_) => _cancelSkipTimer(),
                        onTapCancel: _cancelSkipTimer,
                        child: Container(
                          height: 50, // Slightly increased height for better touch
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey[400]!,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Stack(
                            children: [
                              // Progress indicator
                              if (_isSkipHolding)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 50),
                                  width: MediaQuery.of(context).size.width * 0.4 * _skipProgress,
                                  decoration: BoxDecoration(
                                    color: AppColors.warningOrange.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              
                              // Button content
                              Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.skip_next, 
                                      color: _isSkipHolding ? Colors.white : Colors.grey[700], 
                                      size: 20
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Skip',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: _isSkipHolding ? Colors.white : Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Hold to skip message
                      if (_isSkipHolding)
                        Positioned(
                          top: -25,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.warningOrange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Hold to skip',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _nextQuestion,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primaryYellow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isLastQuestion ? 'Submit' : 'Next',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isLastQuestion ? Icons.done_all : Icons.arrow_forward, 
                          color: Colors.white, 
                          size: 20
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
                'Exit Test?',
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to exit? Your progress will be lost.',
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
                backgroundColor: AppColors.errorRed,
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
}