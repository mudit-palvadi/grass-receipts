/// Grass Receipts — I touched grass and all I got was this absurd receipt.
///
/// Entry for the Hacktoberfest Open-Source AI Challenge Week 1, "Touch Grass":
/// https://dev.to/challenges/hacktoberfest-week1-2026-10-05
library;

import 'package:flutter/material.dart';

import 'ui/screens/receipt_screen.dart';

void main() {
  runApp(const GrassReceiptsApp());
}

class GrassReceiptsApp extends StatelessWidget {
  const GrassReceiptsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grass Receipts',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF101015),
        fontFamily: 'Roboto',
      ),
      home: const ReceiptScreen(),
    );
  }
}
