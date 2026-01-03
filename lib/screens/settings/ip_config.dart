import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

class IpConfigPage extends StatefulWidget {
  const IpConfigPage({Key? key}) : super(key: key);

  @override
  State<IpConfigPage> createState() => _IpConfigPageState();
}

class _IpConfigPageState extends State<IpConfigPage> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers for text fields
  final TextEditingController _publicIpController = TextEditingController();
  final TextEditingController _privateIpController = TextEditingController();
  final TextEditingController _wifiNameController = TextEditingController();
  
  // Current WiFi SSID
  String _currentWifiSsid = 'Not connected';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isConnectedToInstituteWifi = false; // Track if connected to configured Institute WiFi

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
    _getCurrentWifiSsid();
  }

  @override
  void dispose() {
    _publicIpController.dispose();
    _privateIpController.dispose();
    _wifiNameController.dispose();
    super.dispose();
  }

  // Load current IP settings from SharedPreferences
  Future<void> _loadCurrentSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final publicIp = prefs.getString('public_ip') ?? '117.241.73.134';
      final privateIp = prefs.getString('private_ip') ?? '192.168.20.102';
      final wifiName = prefs.getString('institute_wifi_name') ?? 'Coremicron llp';
      
      _publicIpController.text = publicIp;
      _privateIpController.text = privateIp;
      _wifiNameController.text = wifiName;
    } catch (e) {
      _showSnackBar('Error loading settings: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Get current WiFi SSID and check if it matches institute WiFi
  Future<void> _getCurrentWifiSsid() async {
    try {
      final results = await Connectivity().checkConnectivity();
      
      if (results.isNotEmpty && results.first == ConnectivityResult.wifi) {
        final info = NetworkInfo();
        String? wifiName = await info.getWifiName();
        
        if (wifiName != null) {
          if (wifiName.startsWith('"') && wifiName.endsWith('"')) {
            wifiName = wifiName.substring(1, wifiName.length - 1);
          }
          
          // Check if current WiFi matches configured institute WiFi
          final configuredWifiName = _wifiNameController.text.trim().toLowerCase();
          final isInstituteWifi = wifiName.toLowerCase().contains(configuredWifiName);
          
          setState(() {
            _currentWifiSsid = wifiName!;
            _isConnectedToInstituteWifi = isInstituteWifi;
          });
        } else {
          setState(() {
            _currentWifiSsid = 'WiFi (name unavailable)';
            _isConnectedToInstituteWifi = false;
          });
        }
      } else if (results.isNotEmpty && results.first == ConnectivityResult.mobile) {
        setState(() {
          _currentWifiSsid = 'Mobile Data';
          _isConnectedToInstituteWifi = false;
        });
      } else {
        setState(() {
          _currentWifiSsid = 'No connection';
          _isConnectedToInstituteWifi = false;
        });
      }
    } catch (e) {
      setState(() {
        _currentWifiSsid = 'Unable to detect';
        _isConnectedToInstituteWifi = false;
      });
    }
  }

  // Save IP configuration
  Future<void> _saveConfiguration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString('public_ip', _publicIpController.text.trim());
      await prefs.setString('private_ip', _privateIpController.text.trim());
      await prefs.setString('institute_wifi_name', _wifiNameController.text.trim());
      
      _showSnackBar('Configuration saved successfully!', isError: false);
      
      // Re-check WiFi connection after saving to update active indicator
      await _getCurrentWifiSsid();
      
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnackBar('Error saving configuration: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // Reset to default IPs
  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reset to Defaults', style: TextStyle(fontSize: 16)),
        content: const Text(
          'Reset to default IP addresses and WiFi name?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(fontSize: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _publicIpController.text = '117.241.73.134';
        _privateIpController.text = '192.168.20.102';
        _wifiNameController.text = 'Coremicron llp';
      });
      await _getCurrentWifiSsid(); // Update active indicator
      _showSnackBar('Reset to defaults', isError: false);
    }
  }

  // Show snackbar
  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Validate IP address format
  String? _validateIp(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    
    final trimmedValue = value.trim();
    
    // Check if there's a port number
    String ipPart;
    String? portPart;
    
    if (trimmedValue.contains(':')) {
      final parts = trimmedValue.split(':');
      if (parts.length != 2) {
        return 'Invalid format (e.g., 192.168.1.1 or 192.168.1.1:8001)';
      }
      ipPart = parts[0];
      portPart = parts[1];
      
      // Validate port number
      final port = int.tryParse(portPart);
      if (port == null || port < 1 || port > 65535) {
        return 'Port must be 1-65535';
      }
    } else {
      ipPart = trimmedValue;
    }
    
    // Validate IP address part
    final ipPattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    
    if (!ipPattern.hasMatch(ipPart)) {
      return 'Invalid IP format (e.g., 192.168.1.1)';
    }
    
    final octets = ipPart.split('.');
    for (var octet in octets) {
      final num = int.tryParse(octet);
      if (num == null || num < 0 || num > 255) {
        return 'IP octets must be 0-255';
      }
    }
    
    return null;
  }

  // Validate WiFi name
  String? _validateWifiName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'WiFi name is required';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'IP Configuration',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _getCurrentWifiSsid,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // WiFi Status Card - Compact
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).primaryColor.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _currentWifiSsid.contains('WiFi') || 
                            _currentWifiSsid == 'Not connected' ||
                            _currentWifiSsid == 'No connection'
                                ? Icons.wifi_off
                                : _currentWifiSsid == 'Mobile Data'
                                    ? Icons.signal_cellular_alt
                                    : Icons.wifi,
                            color: Theme.of(context).primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current Connection',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currentWifiSsid,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Institute WiFi Name
                    const Text(
                      'Institute WiFi Name',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _wifiNameController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Coremicron llp',
                        hintStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Icon(Icons.wifi, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        filled: true,
                      ),
                      validator: _validateWifiName,
                      onChanged: (value) {
                        // Re-check connection when WiFi name changes
                        _getCurrentWifiSsid();
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter the WiFi name that should use Private IP',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Public IP
                    Row(
                      children: [
                        const Text(
                          'Public IP (External)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (!_isConnectedToInstituteWifi && 
                            _currentWifiSsid != 'No connection' && 
                            _currentWifiSsid != 'Not connected' &&
                            _currentWifiSsid != 'Unable to detect')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.green, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.check_circle, color: Colors.green, size: 12),
                                SizedBox(width: 3),
                                Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _publicIpController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '117.241.73.134',
                        hintStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Icon(Icons.cloud, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        filled: true,
                      ),
                      keyboardType: TextInputType.number,
                      validator: _validateIp,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'For mobile data or other networks',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Private IP
                    Row(
                      children: [
                        const Text(
                          'Private IP (Institute WiFi)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (_isConnectedToInstituteWifi)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.green, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.check_circle, color: Colors.green, size: 12),
                                SizedBox(width: 3),
                                Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _privateIpController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '192.168.20.102 or 192.168.20.102:8001',
                        hintStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Icon(Icons.computer, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        filled: true,
                      ),
                      keyboardType: TextInputType.number,
                      validator: _validateIp,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'When connected to Institute WiFi',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Buttons Row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : _resetToDefaults,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Reset',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveConfiguration,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Save Configuration',
                                    style: TextStyle(fontSize: 13),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Info Card - Compact
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.blue,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Quick Info',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '• Configure your Institute WiFi name\n'
                                  '• Public IP for mobile/external networks\n'
                                  '• Private IP for configured Institute WiFi\n'
                                  '• Auto-switches based on connection\n'
                                  '• Changes take effect after saving',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue[800],
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}