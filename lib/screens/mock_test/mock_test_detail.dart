import 'package:flutter/material.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import '../../common/loading_animations.dart';
import 'package:intl/intl.dart';

class MockTestResultDetailScreen extends StatefulWidget {
  final Map<String, dynamic> resultData;
  final String unitName;
  final String attemptDate;

  const  MockTestResultDetailScreen({
    super.key,
    required this.resultData,
    required this.unitName,
    required this.attemptDate,
  });

  @override
  State<MockTestResultDetailScreen> createState() => _MockTestResultDetailScreenState();
}

class _MockTestResultDetailScreenState extends State<MockTestResultDetailScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final summary = widget.resultData['summary'] ?? {};
    final answers = widget.resultData['answers'] ?? [];
    final totalQuestions = summary['total_questions'] ?? 0;
    final correctAnswers = summary['correct_answers'] ?? 0;
    final score = summary['score'] ?? 0;
    final percentage = totalQuestions > 0 ? (correctAnswers / totalQuestions * 100) : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Test Result Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        backgroundColor: AppColors.primaryYellow,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
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
            stops: [0.0, 0.2, 1.0],
          ),
        ),
        child: _isLoading
            ? _buildLoadingScreen()
            : _buildResultScreen(totalQuestions, correctAnswers, score, percentage, answers),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StaggeredDotsWave(size: Size(80, 60)),
          SizedBox(height: 20),
          Text(
            'Gathering your results...',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultScreen(int totalQuestions, int correctAnswers, int score, double percentage, List<dynamic> answers) {
    return Column(
      children: [
        // Summary Card
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
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
            children: [
              Text(
                widget.unitName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Attempted on: ${_formatDate(widget.attemptDate)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('Total', '$totalQuestions', AppColors.primaryBlue),
                  _buildStatItem('Correct', '$correctAnswers', Colors.green),
                  _buildStatItem('Score', '$score', AppColors.primaryYellow),
                  _buildStatItem('Percentage', '${percentage.toStringAsFixed(1)}%', AppColors.primaryBlue),
                ],
              ),
            ],
          ),
        ),

        // Questions List
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
            child: answers.isEmpty
                ? Center(
                    child: Text(
                      'No question details available',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: answers.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final answer = answers[index];
                      return _buildQuestionItem(index + 1, answer);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String title, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionItem(int questionNumber, Map<String, dynamic> answer) {
    final question = answer['question'] ?? 'No question';
    final options = List<String>.from(answer['options'] ?? []);
    final selectedAnswer = answer['selected_answer'] ?? '';
    final correctAnswer = answer['correct_answer'] ?? '';
    final isCorrect = answer['is_correct'] ?? false;
    final timeTaken = answer['time_taken']?.toString() ?? '0.0';
    final mark = answer['mark'] ?? 0;
    final skipped = answer['skipped'] ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCorrect ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isCorrect ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Q$questionNumber',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (skipped)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warningOrange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Skipped',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${timeTaken}m',
                  style: const TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Mark: $mark',
                  style: const TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            question,
            style: const TextStyle(
              fontSize: 12, 
              fontWeight: FontWeight.w600,
              color: AppColors.primaryBlue,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          ...options.map((option) => _buildOptionItem(
            option,
            selectedAnswer: selectedAnswer,
            correctAnswer: correctAnswer,
          )),
        ],
      ),
    );
  }

  Widget _buildOptionItem(String option, {required String selectedAnswer, required String correctAnswer}) {
    final isSelected = option == selectedAnswer;
    final isCorrect = option == correctAnswer;
    
    Color borderColor = Colors.grey[300]!;
    Color textColor = Colors.black87;
    Color backgroundColor = Colors.white;
    
    if (isSelected && isCorrect) {
      borderColor = Colors.green;
      textColor = Colors.green;
      backgroundColor = Colors.green.withOpacity(0.1);
    } else if (isSelected && !isCorrect) {
      borderColor = Colors.red;
      textColor = Colors.red;
      backgroundColor = Colors.red.withOpacity(0.1);
    } else if (isCorrect) {
      borderColor = Colors.green;
      textColor = Colors.green;
      backgroundColor = Colors.green.withOpacity(0.1);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 20, 
            height: 20,
            decoration: BoxDecoration(
              color: isSelected ? borderColor : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: borderColor,
                width: 2,
              ),
            ),
            child: isSelected
                ? Icon(
                    isCorrect ? Icons.check : Icons.close,
                    color: Colors.white,
                    size: 12, 
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              option,
              style: TextStyle(
                fontSize: 11, 
                color: textColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateString);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }
}