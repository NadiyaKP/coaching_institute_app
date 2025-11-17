import 'package:flutter/material.dart';
import '../../common/theme_color.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

class MockTestResultScreen extends StatelessWidget {
  final Map<String, dynamic> resultData;
  final String unitName;
  final int totalQuestions;
  final int answeredQuestions;
  final List<dynamic> questions;
  final Map<String, int> selectedAnswers;
  final VoidCallback? onBackPressed;

  const MockTestResultScreen({
    super.key,
    required this.resultData,
    required this.unitName,
    required this.totalQuestions,
    required this.answeredQuestions,
    required this.questions,
    required this.selectedAnswers,
    this.onBackPressed,
  });

  

  @override
 Widget build(BuildContext context) {
    final success = resultData['success'] ?? false;
    final summary = resultData['summary'] ?? {};
    final answers = resultData['answers'] ?? [];

    if (!success) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Test Result'),
          backgroundColor: AppColors.primaryYellow,
        ),
        body: const Center(
          child: Text('Failed to load test results'),
        ),
      );
    }

    final totalQuestions = summary['total_questions'] ?? 0;
    final correctAnswers = summary['correct_answers'] ?? 0;
    final score = summary['score'] ?? 0;
    final percentage = totalQuestions > 0 ? (correctAnswers / totalQuestions * 100) : 0;

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (!didPop) {
          await _clearHiveData();
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Test Result',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: AppColors.primaryYellow,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          automaticallyImplyLeading: false,
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
              stops:  [0.0, 0.2, 1.0],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Score Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          unitName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildScoreCircle(
                              'Score',
                              '$score',
                              AppColors.primaryYellow,
                            ),
                            _buildScoreCircle(
                              'Correct',
                              '$correctAnswers/$totalQuestions',
                              AppColors.successGreen,
                            ),
                            _buildScoreCircle(
                              'Percentage',
                              '${percentage.toStringAsFixed(1)}%',
                              AppColors.primaryBlue,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(_getPercentageColor(percentage)),
                          minHeight: 12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getPerformanceText(percentage),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _getPercentageColor(percentage),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Detailed Analysis
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Detailed Analysis',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildAnalysisRow(
                          'Total Questions',
                          '$totalQuestions',
                          Icons.quiz,
                        ),
                        _buildAnalysisRow(
                          'Answered',
                          '$answeredQuestions',
                          Icons.check_circle,
                        ),
                        _buildAnalysisRow(
                          'Correct Answers',
                          '$correctAnswers',
                          Icons.verified,
                        ),
                        _buildAnalysisRow(
                          'Wrong Answers',
                          '${answeredQuestions - correctAnswers}',
                          Icons.cancel,
                        ),
                        _buildAnalysisRow(
                          'Skipped Questions',
                          '${totalQuestions - answeredQuestions}',
                          Icons.next_plan,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Question-wise Results
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Question-wise Results',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...List.generate(questions.length, (index) {
                          final question = questions[index];
                          final questionId = question['question_id'];
                          final questionText = question['question'] ?? 'No question text';
                          final options = question['options'] ?? [];
                          
                          final answer = index < answers.length ? answers[index] : {};
                          final isCorrect = answer['is_correct'] ?? false;
                          final skipped = answer['skipped'] ?? false;
                          final correctOption = answer['correct_option'];
                          final selectedOptionId = selectedAnswers[questionId];
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: skipped 
                                  ? Colors.grey[50]
                                  : (isCorrect 
                                      ? AppColors.successGreen.withOpacity(0.1)
                                      : AppColors.errorRed.withOpacity(0.1)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: skipped
                                    ? Colors.grey[300]!
                                    : (isCorrect
                                        ? AppColors.successGreen.withOpacity(0.3)
                                        : AppColors.errorRed.withOpacity(0.3)),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: skipped
                                            ? Colors.grey
                                            : (isCorrect ? AppColors.successGreen : AppColors.errorRed),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Icon(
                                          skipped
                                              ? Icons.next_plan
                                              : (isCorrect ? Icons.check : Icons.close),
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Question ${index + 1}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      skipped ? 'Skipped' : (isCorrect ? 'Correct' : 'Wrong'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: skipped
                                            ? Colors.grey
                                            : (isCorrect ? AppColors.successGreen : AppColors.errorRed),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  questionText,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                
                                // Show answers for skipped questions
                                if (skipped)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.grey[400]!,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              size: 18,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Question was skipped',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[700],
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (correctOption != null)
                                        _buildAnswerOption(
                                          'Correct Answer:',
                                          _getCorrectOptionText(options, correctOption),
                                          AppColors.successGreen,
                                        ),
                                    ],
                                  ),
                                
                                // Show selected answer and correct answer if answered
                                if (!skipped)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildAnswerOption(
                                        'Your Answer:',
                                        _getSelectedOptionText(options, selectedOptionId),
                                        isCorrect ? AppColors.successGreen : AppColors.errorRed,
                                      ),
                                      if (!isCorrect && correctOption != null)
                                        _buildAnswerOption(
                                          'Correct Answer:',
                                          _getCorrectOptionText(options, correctOption),
                                          AppColors.successGreen,
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await _clearHiveData();
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: AppColors.primaryBlue, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Back to Units',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            await _clearHiveData();
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: AppColors.primaryYellow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          child: const Text(
                            'Try Again',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCircle(String title, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: color,
              width: 3,
            ),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisRow(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: AppColors.primaryYellow,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerOption(String label, String optionText, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              optionText,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getSelectedOptionText(List<dynamic> options, int? selectedOptionId) {
    if (selectedOptionId == null) return 'Not answered';
    
    final selectedOption = options.firstWhere(
      (option) => option['id'] == selectedOptionId,
      orElse: () => {'text': 'Unknown option'},
    );
    
    final optionIndex = options.indexWhere((option) => option['id'] == selectedOptionId);
    final optionLetter = optionIndex >= 0 ? String.fromCharCode(65 + optionIndex) : '?';
    
    return '${optionLetter}. ${selectedOption['text']}';
  }

  String _getCorrectOptionText(List<dynamic> options, int correctOption) {
    final correctOptionData = options.firstWhere(
      (option) => option['id'] == correctOption,
      orElse: () => {'text': 'Unknown option'},
    );
    
    final optionIndex = options.indexWhere((option) => option['id'] == correctOption);
    final optionLetter = optionIndex >= 0 ? String.fromCharCode(65 + optionIndex) : '?';
    
    return '${optionLetter}. ${correctOptionData['text']}';
  }

  Color _getPercentageColor(double percentage) {
    if (percentage >= 80) return AppColors.successGreen;
    if (percentage >= 60) return AppColors.primaryYellow;
    if (percentage >= 40) return AppColors.warningOrange;
    return AppColors.errorRed;
  }

  String _getPerformanceText(double percentage) {
    if (percentage >= 80) return 'Excellent!';
    if (percentage >= 60) return 'Good Job!';
    if (percentage >= 40) return 'Needs Improvement';
    return 'Keep Practicing';
  }

  Future<void> _clearHiveData() async {
    try {
      final mockTestBox = await Hive.openBox('mockTestData');
      await mockTestBox.delete('${_getUnitIdFromData()}_test_data');
      debugPrint('✅ Hive data cleared when leaving result screen');
    } catch (e) {
      debugPrint('Error clearing Hive data: $e');
    }
  }

  String _getUnitIdFromData() {
    // Extract unit ID from the data or use a placeholder
    // You might need to modify this based on your actual data structure
    return unitName.toLowerCase().replaceAll(' ', '_');
  }
}