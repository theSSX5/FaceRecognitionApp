// lib/main.dart
import 'package:flutter/material.dart';
import 'welcome_screen.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'attendee_home_screen.dart';
import 'admin_home_screen.dart';
import 'photographer_home_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Recognition App',
      debugShowCheckedModeBanner: false, 
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => WelcomeScreen(),
        '/login': (context) => LoginScreen(),
        '/signup': (context) => SignUpScreen(),
        '/attendee_home': (context) => AttendeeCheckInScreen(),
        '/admin_home': (context) => AdminHomeScreen(),
        '/photographer_home': (context) => PhotographerHomeScreen(),
      },
    );
  }
}