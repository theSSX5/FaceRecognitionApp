// lib/attendee_home_screen.dart

import 'package:flutter/material.dart';
import 'package:frontend/welcome_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart'; // For MediaType
import 'dart:html' as html; // For web-specific file handling

class AttendeeCheckInScreen extends StatefulWidget {
  @override
  _AttendeeCheckInScreenState createState() => _AttendeeCheckInScreenState();
}

class _AttendeeCheckInScreenState extends State<AttendeeCheckInScreen> {
  final _formKey = GlobalKey<FormState>();
  String eventCode = '';
  html.File? _selectedImage;
  bool isLoading = false;
  final ImagePicker _picker = ImagePicker();
  final storage = FlutterSecureStorage();

  // Function to pick image (for Flutter Web)
  Future<void> _pickImage() async {
    try {
      // Trigger the file picker
      html.FileUploadInputElement uploadInput = html.FileUploadInputElement()
        ..accept = 'image/*';
      uploadInput.click();

      // Listen for file selection
      uploadInput.onChange.listen((event) {
        final files = uploadInput.files;
        if (files != null && files.isNotEmpty) {
          setState(() {
            _selectedImage = files.first;
          });
        }
      });
    } catch (e) {
      _showErrorDialog('Failed to pick image: $e');
    }
  }

  Future<void> _submitCheckIn() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedImage == null) {
      _showErrorDialog('Please select a face photo.');
      return;
    }

    _formKey.currentState!.save();

    setState(() {
      isLoading = true;
    });

    try {
      // Retrieve the JWT token from secure storage
      String? token = await storage.read(key: 'jwt_token');

      if (token == null) {
        _showErrorDialog('User is not authenticated. Please log in again.');
        setState(() {
          isLoading = false;
        });
        return;
      }

      // Read the file as bytes
      final reader = html.FileReader();
      reader.readAsArrayBuffer(_selectedImage!);
      await reader.onLoad.first;
      final bytes = reader.result as Uint8List;

      // Determine the content type based on file extension
      String mimeType = 'image/jpeg'; // Default MIME type
      String fileExtension = _selectedImage!.name.split('.').last.toLowerCase();
      if (fileExtension == 'png') {
        mimeType = 'image/png';
      } else if (fileExtension == 'gif') {
        mimeType = 'image/gif';
      }

      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://localhost:5001/api/attendee/checkin'), // Update with your backend endpoint
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['event_code'] = eventCode;

      // Attach the image file as bytes
      request.files.add(http.MultipartFile.fromBytes(
        'face_photo',
        bytes,
        filename: _selectedImage!.name,
        contentType: MediaType.parse(mimeType),
      ));

      // Send the request
      var streamedResponse = await request.send();

      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        _showSuccessDialog(data['message'] ?? 'Check-in successful!');
        // Optionally, reset the form
        _formKey.currentState?.reset();
        setState(() {
          _selectedImage = null;
        });
      } else {
        var data = jsonDecode(response.body);
        _showErrorDialog(data['message'] ?? 'Check-in failed.');
      }
    } catch (e) {
      _showErrorDialog('An error occurred during check-in: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Check-In Failed'),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            child: Text(
              'Okay',
              style: TextStyle(color: Colors.blueAccent),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
          )
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Check-In Successful'),
        content: Text(
          '$message\n\nYou will receive the image 2/3 business days after the event finishes.',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            child: Text(
              'Great!',
              style: TextStyle(color: Colors.blueAccent),
            ),
            onPressed: () {
              Navigator.of(ctx).pop(); // Close the dialog
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) =>  WelcomeScreen()),
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_selectedImage != null) {
      final objectUrl = html.Url.createObjectUrlFromBlob(_selectedImage!);
      return Column(
        children: [
          SizedBox(height: 20),
          Text(
            'Selected Image:',
            style: TextStyle(color: Colors.black87, fontSize: 16),
          ),
          SizedBox(height: 10),
          Container(
            height: 300, // Fixed height for portrait mode
            width: 200, // Fixed width
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20.0), // Rounded edges
              border: Border.all(color: Colors.grey.shade400, width: 2), // Subtle border
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(2, 2),
                ),
              ], // Optional shadow
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18.0), // Match container's borderRadius
              child: Image.network(
                objectUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Text(
                      'Unable to load image.',
                      style: TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(height: 10),
          // Revoke the object URL after the image is loaded
          () {
            // Delay the revoking to ensure the image has loaded
            Future.delayed(Duration(seconds: 1), () {
              html.Url.revokeObjectUrl(objectUrl);
            });
            return SizedBox.shrink();
          }(),
        ],
      );
    } else {
      return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      // Remove the AppBar entirely
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blueAccent.shade100,
              Colors.blueAccent.shade400,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 700,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Return Button
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        Navigator.of(context).pop(); // Navigate back when pressed
                      },
                      tooltip: 'Return',
                    ),
                  ),
                  SizedBox(height: 10),
                  // Logo
                  Center(
                    child: Icon(
                      Icons.bubble_chart,
                      size: screenSize.height * 0.15,
                      color: Colors.white, // Logo in white
                    ),
                  ),
                  SizedBox(height: 20),
                  // Title
                  Center(
                    child: Text(
                      'Event Check-In',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white, // Dark text on white form
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  // Subtitle
                  Center(
                    child: Text(
                      'Enter your event code and upload your face photo',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white70, // Darker subtitle
                        fontFamily: 'Roboto',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: 40),
                  // Check-In Form Card
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    elevation: 8,
                    shadowColor: Colors.black54,
                    color: Colors.white, // Form box in white
                    child: Padding(
                      padding: const EdgeInsets.all(25.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Event Code Field
                            TextFormField(
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.code, color: Colors.blueAccent),
                                hintText: 'Event Code',
                                hintStyle: TextStyle(color: Colors.blueAccent),
                                filled: true,
                                fillColor: const Color.fromARGB(50, 68, 137, 255), // Gray-ish background
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15.0),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              style: TextStyle(color: Colors.blueAccent),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter the event code';
                                }
                                return null;
                              },
                              onSaved: (value) {
                                eventCode = value ?? '';
                              },
                            ),
                            SizedBox(height: 20),
                            // Face Photo Upload
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedImage == null
                                        ? 'No image selected.'
                                        : 'Selected Image: ${_selectedImage!.name}',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _pickImage,
                                  icon: Icon(Icons.upload_file, color: Colors.white),
                                  label: Text(
                                    'Upload Photo',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent, // Button in blue
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10.0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            _buildImagePreview(),
                            SizedBox(height: 30),
                            // Submit Button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent, // Button in blue
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15.0),
                                  ),
                                ),
                                child: isLoading
                                    ? CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(Colors.white),
                                      )
                                    : Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                onPressed: isLoading ? null : _submitCheckIn,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20), // Add some space at the bottom
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}