// lib/signup_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_screen.dart'; // Ensure this path is correct
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Import secure storage
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Import Font Awesome for bubble icon

class SignUpScreen extends StatefulWidget {
  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  String email = '';
  String password = '';
  String name = '';
  String? role; // Role can be 'attendee' or 'photographer'

  bool isLoading = false; // Add a loading state
  bool _isPasswordVisible = false; // Password visibility toggle

  final storage = FlutterSecureStorage(); // Initialize secure storage

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) {
      // Invalid input
      return;
    }

    _formKey.currentState!.save();

    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://localhost:5001/api/auth/register'), // Updated endpoint
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'name': name,
          'role': role,
        }),
      );

      if (response.statusCode == 201) {
        // Navigate to login screen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration successful. Please log in.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        final data = jsonDecode(response.body);
        _showErrorDialog(data['message'] ?? 'Sign-up failed.');
      }
    } catch (e) {
      _showErrorDialog('An error occurred during sign-up.');
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
        title: Text('Sign Up Failed'),
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

  // Helper method to format the date string (if needed)
  String _formatDate(String dateStr) {
    try {
      DateTime dateTime = DateTime.parse(dateStr);
      return "${dateTime.day}/${dateTime.month}/${dateTime.year}";
    } catch (e) {
      print('Error formatting date: $e');
      return dateStr; // Return the original string if parsing fails
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define screen size for responsiveness
    final Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
            padding:
                const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 700, // Set maximum width to prevent over-expanding
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Bubble Icon as Logo
                  Icon(
                    Icons.bubble_chart, // Using bubble-like icon
                    size: screenSize.height * 0.15,
                    color: Colors.white,
                  ),
                  SizedBox(height: 20),
                  // Title
                  Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  SizedBox(height: 10),
                  // Subtitle
                  Text(
                    'Sign up to get started',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  SizedBox(height: 40),
                  // Sign Up Form Card
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    elevation: 8,
                    shadowColor: Colors.black54,
                    child: Padding(
                      padding: const EdgeInsets.all(25.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Name Field
                            TextFormField(
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.person_outline),
                                hintText: 'Name',
                                filled: true,
                                fillColor:
                                    const Color.fromARGB(50, 68, 137, 255),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15.0),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your name';
                                }
                                return null;
                              },
                              onSaved: (value) {
                                name = value ?? '';
                              },
                            ),
                            SizedBox(height: 20),
                            // Email Field
                            TextFormField(
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.email_outlined),
                                hintText: 'Email',
                                filled: true,
                                fillColor:
                                    const Color.fromARGB(50, 68, 137, 255),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15.0),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null ||
                                    value.isEmpty ||
                                    !value.contains('@')) {
                                  return 'Please enter a valid email';
                                }
                                return null;
                              },
                              onSaved: (value) {
                                email = value ?? '';
                              },
                            ),
                            SizedBox(height: 20),
                            // Password Field
                            TextFormField(
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.lock_outline),
                                hintText: 'Password',
                                filled: true,
                                fillColor:
                                    const Color.fromARGB(50, 68, 137, 255),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15.0),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    // Toggle password visibility
                                    _isPasswordVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isPasswordVisible =
                                          !_isPasswordVisible;
                                    });
                                  },
                                ),
                              ),
                              obscureText: !_isPasswordVisible,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                } else if (value.length < 6) {
                                  return 'Password must be at least 6 characters';
                                }
                                return null;
                              },
                              onSaved: (value) {
                                password = value ?? '';
                              },
                            ),
                            SizedBox(height: 20),
                            // Role Selection Dropdown
                            DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.group_outlined),
                                hintText: 'Select Role',
                                filled: true,
                                fillColor:
                                    const Color.fromARGB(50, 68, 137, 255),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15.0),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              value: role,
                              items: <String>['Attendee', 'Photographer']
                                  .map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value.toLowerCase(),
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                setState(() {
                                  role = newValue;
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select your role';
                                }
                                return null;
                              },
                              onSaved: (value) {
                                role = value;
                              },
                            ),
                            SizedBox(height: 30),
                            // Sign Up Button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Colors.blueAccent, // Button color
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15.0),
                                  ),
                                ),
                                child: isLoading
                                    ? CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      )
                                    : Text(
                                        'Sign Up',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        if (_formKey.currentState
                                                ?.validate() ??
                                            false) {
                                          _formKey.currentState?.save();
                                          _signup();
                                        }
                                      },
                              ),
                            ),
                            SizedBox(height: 20),
                            // OR Divider
                            Row(
                              children: [
                                Expanded(
                                  child: Divider(
                                    color: Colors.grey,
                                    thickness: 1,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10.0),
                                  child: Text(
                                    'OR',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(
                                    color: Colors.grey,
                                    thickness: 1,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 30),
                            // Remove Social Login Buttons
                            // If you ever want to add them back, you can uncomment the following section
                            /*
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Google Login
                                ElevatedButton.icon(
                                  onPressed: () {
                                    // Implement Google login
                                  },
                                  icon: Icon(
                                    Icons.login,
                                    color: Colors.white,
                                  ),
                                  label: Text('Google'),
                                  style: ElevatedButton.styleFrom(
                                    primary: Colors.redAccent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(30.0),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 20),
                                // Facebook Login
                                ElevatedButton.icon(
                                  onPressed: () {
                                    // Implement Facebook login
                                  },
                                  icon: Icon(
                                    Icons.login,
                                    color: Colors.white,
                                  ),
                                  label: Text('Facebook'),
                                  style: ElevatedButton.styleFrom(
                                    primary: Colors.blue.shade800,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(30.0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            */
                            SizedBox(height: 30),
                            // Login Prompt
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Already have an account?',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 16,
                                  ),
                                ),
                                TextButton(
                                  child: Text(
                                    'Log In',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueAccent,
                                      fontSize: 16,
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
              )],
                ),
              ),
            ),
          ),
        )
    );
      }
    }