import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async'; 
import 'package:intl/intl.dart';
import 'package:file_selector/file_selector.dart';
import '../../common/theme_color.dart';
import '../../service/api_config.dart';
import '../../service/auth_service.dart';
import '../my_documents/view_documents.dart';

class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({Key? key}) : super(key: key);

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  List<Document> _documents = [];
  Document? _cvDocument;
  Map<String, List<Document>> _groupedDocuments = {};
  Map<String, bool> _expandedSections = {}; 
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isFetchingDocuments = false; 
  String _errorMessage = '';
  String? _accessToken;
  final AuthService _authService = AuthService();
  
  // Document type options for dropdown
  final List<String> _documentTypes = [
    'CERTIFICATE',
    'MARKLIST',
    'ACHIEVEMENT',
    'OTHER',
  ];
  
  String _selectedDocumentType = 'CERTIFICATE';
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    await _getAccessToken();
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await _fetchDocuments();
    } else {
      _showError('Access token not found. Please login again.');
      _navigateToLogin();
    }
  }

  Future<void> _getAccessToken() async {
    try {
      _accessToken = await _authService.getAccessToken();
    } catch (e) {
      _showError('Failed to retrieve access token: $e');
    }
  }

  // Check if string contains emoji
  bool _containsEmoji(String text) {
    final emojiRegex = RegExp(
      r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{1FA70}-\u{1FAFF}]|[\u{FE00}-\u{FE0F}]|[\u{1F018}-\u{1F270}]|[\u{238C}-\u{2454}]|[\u{20D0}-\u{20FF}]',
      unicode: true,
    );
    return emojiRegex.hasMatch(text);
  }

  // Create HTTP client with custom certificate handling
  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  // Helper method to get authorization headers
  Map<String, String> _getAuthHeaders() {
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw Exception('Access token is null or empty');
    }
    
    return {
      'Authorization': 'Bearer $_accessToken',
      ...ApiConfig.commonHeaders,
    };
  }

  // Helper method to handle token expiration
  void _handleTokenExpiration() async {
    await _authService.logout();
    _showError('Session expired. Please login again.');
    _navigateToLogin();
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  }

  // Fetch all documents from API
  Future<void> _fetchDocuments() async {
    
    if (_isFetchingDocuments) {
      debugPrint('⏳ Documents fetch already in progress, skipping...');
      return;
    }

    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _isFetchingDocuments = true; 
    });

    final client = _createHttpClientWithCustomCert();

    try {
      final apiUrl = '${ApiConfig.currentBaseUrl}/api/students/documents/';
      
      debugPrint('=== FETCHING DOCUMENTS API CALL ===');
      debugPrint('URL: $apiUrl');
      debugPrint('Method: GET');
      debugPrint('Headers: ${_getAuthHeaders()}');
      
      final response = await client.get(
        Uri.parse(apiUrl),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('\n=== DOCUMENTS API RESPONSE ===');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Headers: ${response.headers}');
    
      try {
        final responseJson = jsonDecode(response.body);
        debugPrint('Response Body (Formatted):');
        debugPrint(const JsonEncoder.withIndent('  ').convert(responseJson));
      } catch (e) {
        debugPrint('Response Body: ${response.body}');
      }
      debugPrint('=== END DOCUMENTS API RESPONSE ===\n');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          final List<dynamic> documentsJson = data['documents'] ?? [];
          
          setState(() {
            _documents = documentsJson
                .map((json) => Document.fromJson(json))
                .toList();
            _isLoading = false;
          });

          // Categorize documents - separate CV from others and group by type
          _categorizeDocuments();
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch documents');
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        _showError('SSL certificate issue - please try again');
      }
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      setState(() => _isLoading = false);
      
      if (mounted) {
        _showError('No network connection');
      }
    } on TimeoutException catch (e) {
      debugPrint('Timeout error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        _showError('Request timeout - please try again');
      }
    } catch (e) {
      debugPrint('Error fetching documents: $e');
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    
      if (mounted) {
        _showError('Failed to fetch documents: ${e.toString().replaceAll("Exception: ", "")}');
      }
    } finally {
      client.close();
     
      _isFetchingDocuments = false;
    }
  }

  // Categorize documents into CV and grouped by type
  void _categorizeDocuments() {
    setState(() {
      _cvDocument = _documents.firstWhere(
        (doc) => doc.documentType == 'CV',
        orElse: () => Document(
          id: '',
          documentType: '',
          title: '',
          fileUrl: '',
          uploadedAt: '',
          verified: false,
          isPublic: false,
        ),
      );
      
      if (_cvDocument?.id.isEmpty ?? true) {
        _cvDocument = null;
      }
      
      // Group other documents by type
      _groupedDocuments = {};
      for (var doc in _documents) {
        if (doc.documentType != 'CV') {
          if (!_groupedDocuments.containsKey(doc.documentType)) {
            _groupedDocuments[doc.documentType] = [];
            // Initialize all sections as collapsed
            _expandedSections[doc.documentType] = false;
          }
          _groupedDocuments[doc.documentType]!.add(doc);
        }
      }
    });
    
    debugPrint('CV Document: ${_cvDocument?.title ?? 'None'}');
    debugPrint('Grouped Documents: ${_groupedDocuments.keys.toList()}');
  }

  Future<void> _uploadDocument(String documentType, String title, XFile file) async {
    setState(() {
      _isUploading = true;
    });
    
    final client = _createHttpClientWithCustomCert();
    
    try {
      final apiUrl = '${ApiConfig.currentBaseUrl}/api/students/upload_document/';
      
      debugPrint('=== UPLOADING DOCUMENT ===');
      debugPrint('URL: $apiUrl');
      debugPrint('Document Type: $documentType');
      debugPrint('Title: $title');
      debugPrint('File Name: ${file.name}');
      
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.headers.addAll(_getAuthHeaders());
      
      // Add form fields
      request.fields['document_type'] = documentType;
      request.fields['title'] = title;
      
      // Read file bytes and add to request
      final bytes = await file.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.name,
      ));
      
      debugPrint('Sending upload request...');
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      debugPrint('\n=== UPLOAD RESPONSE ===');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Body: ${response.body}');
      debugPrint('=== END UPLOAD RESPONSE ===\n');
      
      setState(() {
        _isUploading = false;
      });
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  data['message'] ?? 'Document uploaded successfully!'
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        
          await Future.delayed(const Duration(milliseconds: 800));
          await _fetchDocuments();
        } else {
          throw Exception(data['message'] ?? 'Upload failed');
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Server error: ${response.statusCode}');
      }
    } on TimeoutException catch (e) {
      setState(() {
        _isUploading = false;
      });
      debugPrint('Upload timeout: $e');
      _showError('Upload timeout - please try again');
    } on SocketException catch (e) {
      setState(() {
        _isUploading = false;
      });
      debugPrint('Network error during upload: $e');
      _showError('Network error - please check your connection');
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      debugPrint('Error uploading document: $e');
      _showError('Failed to upload document: ${e.toString().replaceAll("Exception: ", "")}');
    } finally {
      client.close();
    }
  }

  // Delete document
  Future<void> _deleteDocument(String documentId) async {
    final client = _createHttpClientWithCustomCert();
    
    try {
      final apiUrl = '${ApiConfig.currentBaseUrl}/api/students/document/$documentId/delete/';
      
      debugPrint('=== DELETING DOCUMENT ===');
      debugPrint('URL: $apiUrl');
      debugPrint('Document ID: $documentId');
      
      final response = await client.delete(
        Uri.parse(apiUrl),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);
      
      debugPrint('\n=== DELETE RESPONSE ===');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Body: ${response.body}');
      debugPrint('=== END DELETE RESPONSE ===\n');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  data['message'] ?? 'Document deleted successfully!'
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Refresh documents list
          await _fetchDocuments();
        } else {
          throw Exception(data['message'] ?? 'Delete failed');
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } on TimeoutException catch (e) {
      debugPrint('Delete timeout: $e');
      _showError('Delete timeout - please try again');
    } on SocketException catch (e) {
      debugPrint('Network error during delete: $e');
      _showError('Network error - please check your connection');
    } catch (e) {
      debugPrint('Error deleting document: $e');
      _showError('Failed to delete document: ${e.toString().replaceAll("Exception: ", "")}');
    } finally {
      client.close();
    }
  }

  // Pick and upload CV
  Future<void> _pickAndUploadCV({bool isReupload = false}) async {
    try {
      const XTypeGroup fileTypeGroup = XTypeGroup(
        label: 'PDF Documents',
        extensions: ['pdf'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: [fileTypeGroup],
      );

      if (file != null) {
        String fileName = file.name;
        
        if (!fileName.toLowerCase().endsWith('.pdf')) {
          _showError('Only PDF files are allowed');
          return;
        }
        
        int fileSizeInBytes = await file.length();
        double fileSizeInMB = fileSizeInBytes / (1024 * 1024);
        
        if (fileSizeInMB > 10) {
          _showError('File size must be less than 10MB');
          return;
        }

        await _showTitleInputDialog('CV', file, isReupload: isReupload);
      }
    } catch (e) {
      debugPrint('Error picking CV: $e');
      _showError('Failed to pick file: ${e.toString()}');
    }
  }

  Future<void> _pickAndUploadOtherDocument() async {
    try {
      const XTypeGroup fileTypeGroup = XTypeGroup(
        label: 'PDF Documents',
        extensions: ['pdf'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: [fileTypeGroup],
      );

      if (file != null) {
        String fileName = file.name;
        
        // Validate file extension
        if (!fileName.toLowerCase().endsWith('.pdf')) {
          _showError('Only PDF files are allowed');
          return;
        }
        
        int fileSizeInBytes = await file.length();
        double fileSizeInMB = fileSizeInBytes / (1024 * 1024);
        
        if (fileSizeInMB > 10) {
          _showError('File size must be less than 10MB');
          return;
        }

        // Show document type and title input dialog
        await _showDocumentUploadDialog(file);
      }
    } catch (e) {
      debugPrint('Error picking document: $e');
      _showError('Failed to pick file: ${e.toString()}');
    }
  }

  // Show title input dialog for CV
  Future<void> _showTitleInputDialog(String documentType, XFile file, {bool isReupload = false}) async {
    _titleController.clear();
    if (isReupload && _cvDocument != null) {
      _titleController.text = _cvDocument!.title;
    }
    
    bool? shouldUpload = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                isReupload ? Icons.replay_rounded : Icons.upload_rounded,
                color: AppColors.primaryYellow,
              ),
              const SizedBox(width: 8),
              Text(
                isReupload ? 'Reupload CV' : 'Upload CV',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'File: ${file.name}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textGrey,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                inputFormatters: [
                  // Filter out emojis
                  FilteringTextInputFormatter.deny(
                    RegExp(
                      r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{1FA70}-\u{1FAFF}]|[\u{FE00}-\u{FE0F}]|[\u{1F018}-\u{1F270}]|[\u{238C}-\u{2454}]|[\u{20D0}-\u{20FF}]',
                      unicode: true,
                    ),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g., My Resume 2025',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.primaryYellow,
                      width: 2,
                    ),
                  ),
                ),
              ),
              if (isReupload) ...[
                const SizedBox(height: 12),
                Text(
                  'Note: This will replace your current CV.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textGrey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                // Check for emojis before submitting
                if (_containsEmoji(_titleController.text)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Emojis are not allowed in title'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.white,
              ),
              child: const Text('Upload'),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );

    if (shouldUpload == true) {
      // Use file name as title if title is empty
      String title = _titleController.text.trim().isEmpty 
          ? file.name.replaceAll('.pdf', '') 
          : _titleController.text.trim();
      await _uploadDocument(documentType, title, file);
    }
  }

  // Show document upload dialog with type selection
  Future<void> _showDocumentUploadDialog(XFile file) async {
    _titleController.clear();
    String selectedType = _selectedDocumentType;
    
    bool? shouldUpload = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(
                    Icons.upload_file_rounded,
                    color: AppColors.primaryYellow,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Upload Document',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'File: ${file.name}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: InputDecoration(
                        labelText: 'Document Type',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.primaryYellow,
                            width: 2,
                          ),
                        ),
                      ),
                      items: _documentTypes.map((String type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(_formatDocumentType(type)),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setDialogState(() {
                            selectedType = newValue;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      inputFormatters: [
                        // Filter out emojis
                        FilteringTextInputFormatter.deny(
                          RegExp(
                            r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{1FA70}-\u{1FAFF}]|[\u{FE00}-\u{FE0F}]|[\u{1F018}-\u{1F270}]|[\u{238C}-\u{2454}]|[\u{20D0}-\u{20FF}]',
                            unicode: true,
                          ),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Title',
                        hintText: 'e.g., Degree Certificate',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.primaryYellow,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textGrey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Check for emojis before submitting
                    if (_containsEmoji(_titleController.text)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Emojis are not allowed in title'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryYellow,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Upload'),
                ),
              ],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            );
          },
        );
      },
    );

    if (shouldUpload == true) {
      // Use file name as title if title is empty
      String title = _titleController.text.trim().isEmpty 
          ? file.name.replaceAll('.pdf', '') 
          : _titleController.text.trim();
      await _uploadDocument(selectedType, title, file);
    }
  }

  // Show delete confirmation dialog
  Future<void> _showDeleteConfirmationDialog(Document document) async {
    bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: Colors.red,
              ),
              SizedBox(width: 8),
              Text(
                'Delete Document',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to delete this document?',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDocumentType(document.documentType),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This action cannot be undone.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textGrey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );

    if (shouldDelete == true) {
      await _deleteDocument(document.id);
    }
  }

  // Open PDF in-app
  void _openPdfInApp(String fileUrl, String fileName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewDocumentsScreen(
          fileUrl: fileUrl,
          fileName: fileName,
        ),
      ),
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatDocumentType(String type) {
    switch (type) {
      case 'CV':
        return 'CV/Resume';
      case 'CERTIFICATE':
        return 'Certificate';
      case 'MARKLIST':
        return 'Mark List';
      case 'ACHIEVEMENT':
        return 'Achievement';
      case 'OTHER':
        return 'Other';
      default:
        return type;
    }
  }

  String _getPluralDocumentType(String type) {
    switch (type) {
      case 'CERTIFICATE':
        return 'Certificates';
      case 'MARKLIST':
        return 'Mark Lists';
      case 'ACHIEVEMENT':
        return 'Achievements';
      case 'OTHER':
        return 'Other Documents';
      default:
        return type;
    }
  }

  IconData _getDocumentTypeIcon(String type) {
    switch (type) {
      case 'CV':
        return Icons.description_rounded;
      case 'CERTIFICATE':
        return Icons.card_membership_rounded;
      case 'MARKLIST':
        return Icons.format_list_numbered_rounded;
      case 'ACHIEVEMENT':
        return Icons.emoji_events_rounded;
      case 'OTHER':
        return Icons.folder_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getDocumentTypeColor(String type) {
    switch (type) {
      case 'CV':
        return Colors.blue;
      case 'CERTIFICATE':
        return Colors.green;
      case 'MARKLIST':
        return Colors.orange;
      case 'ACHIEVEMENT':
        return Colors.purple;
      case 'OTHER':
        return Colors.teal;
      default:
        return AppColors.primaryYellow;
    }
  }

  Widget _buildSkeletonLoader() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // CV Section Skeleton
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 100,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Other Documents Skeleton
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 150,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(3, (index) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
              )),
            ],
          ),
        ),
      ],
    );
  }

  // Build CV section
  Widget _buildCVSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryYellow.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.description_rounded,
                color: Colors.blue,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'CV / Resume',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_cvDocument == null)
            // No CV uploaded - Show upload button
            InkWell(
              onTap: _pickAndUploadCV,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                    style: BorderStyle.solid,
                    width: 2,
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      color: Colors.blue,
                      size: 40,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Upload Your CV',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tap to upload CV in PDF format',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            // CV uploaded - Show document card
            _buildDocumentCard(_cvDocument!, isCV: true),
        ],
      ),
    );
  }

  // Build other documents section with grouping
  Widget _buildOtherDocumentsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryYellow.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.folder_open_rounded,
                color: AppColors.primaryYellow,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Other Documents',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Upload button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pickAndUploadOtherDocument,
              icon: const Icon(Icons.add, size: 20),
              label: const Text(
                'Upload Document',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          
          if (_groupedDocuments.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            
            // Display documents grouped by type
            ..._buildGroupedDocumentsList(),
          ] else ...[
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.folder_off_outlined,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No documents uploaded yet',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build grouped documents list with collapsible sections
  List<Widget> _buildGroupedDocumentsList() {
    List<Widget> widgets = [];
    
    // Define the order of document types
    final orderedTypes = ['CERTIFICATE', 'MARKLIST', 'ACHIEVEMENT', 'OTHER'];
    
    for (String type in orderedTypes) {
      if (_groupedDocuments.containsKey(type) && _groupedDocuments[type]!.isNotEmpty) {
        final documents = _groupedDocuments[type]!;
        final typeColor = _getDocumentTypeColor(type);
        final isExpanded = _expandedSections[type] ?? false;
        
        // Add collapsible section header
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: InkWell(
              onTap: () {
                setState(() {
                  _expandedSections[type] = !isExpanded;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: typeColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getDocumentTypeIcon(type),
                      color: typeColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _getPluralDocumentType(type),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${documents.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isExpanded 
                          ? Icons.keyboard_arrow_up_rounded 
                          : Icons.keyboard_arrow_down_rounded,
                      color: typeColor,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        
        // Add documents for this type (only if expanded)
        if (isExpanded) {
          for (var doc in documents) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
                child: _buildDocumentCard(doc),
              ),
            );
          }
        }
      }
    }
    
    return widgets;
  }

  // Build document card
  Widget _buildDocumentCard(Document document, {bool isCV = false}) {
    final Color typeColor = _getDocumentTypeColor(document.documentType);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: typeColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: typeColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  _getDocumentTypeIcon(document.documentType),
                  color: typeColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (!isCV)
                          Text(
                            _formatDocumentType(document.documentType),
                            style: TextStyle(
                              fontSize: 11,
                              color: typeColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (document.verified) ...[
                          if (!isCV) const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 10,
                                  color: Colors.green,
                                ),
                                SizedBox(width: 2),
                                Text(
                                  'Verified',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Uploaded on ${_formatDate(document.uploadedAt)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openPdfInApp(
                    document.fileUrl,
                    document.title,
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text(
                    'View',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: typeColor,
                    side: BorderSide(color: typeColor),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              if (isCV) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickAndUploadCV(isReupload: true),
                    icon: const Icon(Icons.replay_rounded, size: 16),
                    label: const Text(
                      'Reupload',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _showDeleteConfirmationDialog(document),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  minimumSize: const Size(0, 0),
                ),
                child: const Icon(Icons.delete_outline, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.backgroundLight,
          body: Column(
            children: [
              // Header Section with Curved Bottom
              ClipPath(
                clipper: CurvedHeaderClipper(),
                child: Container(
                  width: double.infinity,
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
                  padding: const EdgeInsets.fromLTRB(16, 50, 16, 30),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'My Documents',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Main Content
              Expanded(
                child: _isLoading
                    ? _buildSkeletonLoader()
                    : _errorMessage.isNotEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textGrey,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _fetchDocuments,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryYellow,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchDocuments,
                            color: AppColors.primaryYellow,
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                // CV Section
                                _buildCVSection(),
                                
                                const SizedBox(height: 16),
                                
                                // Other Documents Section
                                _buildOtherDocumentsSection(),
                                
                                const SizedBox(height: 20),
                                
                                // Info card
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.blue.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Colors.blue[700],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'All documents should be in PDF format and less than 10MB in size.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textDark,
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
            ],
          ),
        ),
        
        // Upload Loading Overlay
        if (_isUploading)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Uploading document...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please wait',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Document Model
class Document {
  final String id;
  final String documentType;
  final String title;
  final String fileUrl;
  final String uploadedAt;
  final bool verified;
  final bool isPublic;

  Document({
    required this.id,
    required this.documentType,
    required this.title,
    required this.fileUrl,
    required this.uploadedAt,
    required this.verified,
    required this.isPublic,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] ?? '',
      documentType: json['document_type'] ?? '',
      title: json['title'] ?? '',
      fileUrl: json['file_url'] ?? '',
      uploadedAt: json['uploaded_at'] ?? '',
      verified: json['verified'] ?? false,
      isPublic: json['is_public'] ?? false,
    );
  }
}

// Curved Header Clipper
class CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 25);
    
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 25,
    );
    
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CurvedHeaderClipper oldClipper) => false;
}