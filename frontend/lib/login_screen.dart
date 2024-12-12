// lib/login_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'user_model.dart';
import 'attendee_home_screen.dart';
import 'admin_home_screen.dart';
import 'photographer_home_screen.dart';
import 'dart:html' as html;
import 'welcome_screen.dart';
import 'signup_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Import secure storage
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Import Font Awesome for bubble icon

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String email = '';
  String password = '';
  final storage = FlutterSecureStorage(); // Initialize secure storage

  bool isLoading = false; // Add a loading state

  Future<void> _login() async {
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
        Uri.parse('http://localhost:5001/api/auth/login'), // Updated endpoint
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String role = data['role'];
        String accessToken = data['access_token'];
        String name = data['name'];

        // Store user information
        UserModel.instance.email = email;
        UserModel.instance.role = role;
        await storage.write(key: 'jwt_token', value: accessToken);
        await storage.write(key: 'user_name', value: name); // Store user name

        html.window.localStorage['jwt_token'] = accessToken;
        html.window.localStorage['user_role'] = role; 

        // Navigate to the appropriate home screen
        _navigateToHomeScreen(role);
      } else {
        final data = jsonDecode(response.body);
        _showErrorDialog(data['message'] ?? 'Login failed.');
      }
    } catch (e) {
      _showErrorDialog('An error occurred during login.');
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
        title: Text('Login Failed'),
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

  void _navigateToHomeScreen(String role) {
    Widget homeScreen;
    if (role == 'attendee') {
      homeScreen = AttendeeCheckInScreen();
    } else if (role == 'admin') {
      homeScreen = AdminHomeScreen();
    } else if (role == 'photographer') {
      homeScreen = PhotographerHomeScreen();
    } else {
      homeScreen = WelcomeScreen();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => homeScreen),
    );
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
                    'Welcome Back',
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
                    'Log in to your account',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  SizedBox(height: 40),
                  // Login Form Card
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
                            // Email Field
                            TextFormField(
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.email_outlined),
                                hintText: 'Email',
                                filled: true,
                                fillColor: const Color.fromARGB(50, 68, 137, 255),
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
                                fillColor: const Color.fromARGB(50, 68, 137, 255),
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
                            SizedBox(height: 30),
                            // Login Button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent, // Button color
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
                                        'Log In',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color:  Colors.white,
                                        ),
                                      ),
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        if (_formKey.currentState
                                                ?.validate() ??
                                            false) {
                                          _formKey.currentState?.save();
                                          _login();
                                        }
                                      },
                              ),
                            ),
                            SizedBox(height: 20),
                            // Forgot Password
                            TextButton(
                              onPressed: () {
                                // Implement forgot password functionality
                                // For example, navigate to ForgotPasswordScreen()
                              },
                              child: Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SizedBox(height: 10),
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
                            SizedBox(height: 20),
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
                            // Sign Up Prompt
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Don\'t have an account?',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 16,
                                  ),
                                ),
                                TextButton(
                                  child: Text(
                                    'Sign Up',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueAccent,
                                      fontSize: 16,
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => SignUpScreen()),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
            ),
              ),
            ),
          ),
        );
      }

      // Helper method to format the date string
      String _formatDate(String dateStr) {
        try {
          DateTime dateTime = DateTime.parse(dateStr);
          return "${dateTime.day}/${dateTime.month}/${dateTime.year}";
        } catch (e) {
          print('Error formatting date: $e');
          return dateStr; // Return the original string if parsing fails
        }
      }

      // Password visibility toggle state
      bool _isPasswordVisible = false;
    }