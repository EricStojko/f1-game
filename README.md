# LIGHTS OUT 🏎️🚥

**LIGHTS OUT** is a fast-paced reaction time game built with Flutter that simulates the high-pressure environment of a professional motorsport race start. Test your reflexes and see if you have the reaction times of a world champion!

---

> **🤖 Notice:** This project was developed from scratch with the assistance of an AI Coding Agent (Google DeepMind / Antigravity).

---

## 🚦 How to Play

1. **Tap to Start:** Initiate the starting sequence.
2. **Hold...:** The 5 red lights will illuminate one by one, accompanied by a sound effect.
3. **Wait for the random delay:** Once all 5 lights are on, there will be a random delay (between 1 and 5 seconds).
4. **GO GO GO!** The moment the lights go out, tap the screen as fast as possible.
5. **Don't Jump the Gun:** If you tap before the lights go out, it's a **FALSE START** and you'll have to try again!

## 🌟 Features

*   **Precise Timing:** Calculates your reaction time down to the millisecond.
*   **Performance Tiers:** Your reaction time dictates your result:
    *   👽 **POLE POSITION** (< 220ms)
    *   🏁 **PODIUM FINISH** (< 300ms)
    *   🟡 **MIDFIELD** (< 400ms)
    *   🐌 **PIT STOP CREW** (> 400ms)
*   **Immersive Effects:** 
    *   Sound effects for lights on, lights out, false starts, and results.
    *   Haptic feedback and visual screen shake on false starts.
    *   Visual flash-bang effect when the lights go out.
*   **Live Telemetry:** A dynamic, custom-painted graph displays your session history in real-time.
*   **Global Standings:** Compete against yourself or friends. The local leaderboard saves the Top 10 fastest times using `shared_preferences`.
*   **Customizable Driver Name:** Register your driver name before you race.

## 🛠️ Technology Stack

*   **Framework:** Flutter
*   **Key Packages:**
    *   `audioplayers`: For immersive racing sound effects.
    *   `shared_preferences`: For persisting leaderboard data locally.
    *   `flutter/services`: For haptic feedback (vibrations).
*   **Architecture:** Currently implemented as a rapid prototype in a single-file architecture to quickly iterate on the game loop and visual aesthetics.

## 🚀 Getting Started

To run this project locally, ensure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.

1.  Clone this repository.
2.  Run `flutter pub get` to install dependencies.
3.  Run the application on an emulator or physical device using `flutter run`. (A physical device is recommended for accurate reaction times and haptic feedback!)

---
*Developed as a fun, interactive way to test reflexes while exploring Flutter animations, custom painters, and audio integration.*
