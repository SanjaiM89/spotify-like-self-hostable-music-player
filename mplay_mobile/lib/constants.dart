import 'package:flutter/material.dart';

// Replace with your backend IP
// For same WiFi: use local IP. For public: use tunnel but streaming has issues
const String baseUrl = 'http://146.70.142.134:47409'; 
const String wsUrl = 'ws://146.70.142.134:47409/ws';

// Colors

const Color kPrimaryColor = Color(0xFFEC4899); // Pink-500
const Color kSecondaryColor = Color(0xFF9333EA); // Purple-600
const Color kBackgroundColor = Color(0xFF0F172A); // Slate-900 (Dark background)

// Constants
const double kPadding = 16.0;
const double kBorderRadius = 16.0;
