import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(const F1ReactionGame());
  });
}

class F1ReactionGame extends StatelessWidget {
  const F1ReactionGame({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LIGHTS OUT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A), // Extremely deep black
        fontFamily: 'Roboto',
        primarySwatch: Colors.red,
      ),
      home: const GameScreen(),
    );
  }
}
