import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/score.dart';
import '../painters/grid_painter.dart';
import '../painters/graph_painter.dart';
import '../painters/carbon_fiber_painter.dart';
import '../painters/checkered_flag_painter.dart';
import '../painters/track_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  static const int _eliteThresholdMs = 220;
  static const int _gridThresholdMs = 300;
  static const int _rookieThresholdMs = 400;
  static const int _minDelayMs = 1000;
  static const int _additionalDelayRangeMs = 4001;
  static const int _leaderboardCap = 10;
  static const int _sessionHistoryCap = 20;
  static const String _prefsKey = 'f1_leaderboard_pro';

  GameState _gameState = GameState.idle;
  int _lightsLit = 0;
  Timer? _sequenceTimer;
  Timer? _randomDelayTimer;
  Timer? _cooldownTimer;
  final Stopwatch _stopwatch = Stopwatch();
  int? _reactionTime;
  String _playerName = "Driver 1";
  bool _isLeaderboardOpen = false;
  bool _isCooldown = false;

  final AudioPlayer _clickPlayer = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();

  List<Score> _leaderboard = [];
  final List<int> _sessionHistory = [];

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _checkeredController;
  late Animation<double> _checkeredAnimation;

  // Idle breathing glow on the gantry lights
  late AnimationController _idleController;
  late Animation<double> _idleAnimation;

  // Cinematic red afterglow when lights go out (replaces jarring white flash)
  late AnimationController _lightsOutController;
  late Animation<double> _lightsOutGlowAnimation;

  // Personal best tracking
  int? _personalBestTime;
  bool _isNewPersonalBest = false;

  // Streak / combo tracking
  int _currentStreak = 0;
  int _bestStreak = 0;

  bool get _isGameActive =>
      _gameState == GameState.starting ||
      _gameState == GameState.waitingForLightsOut ||
      _gameState == GameState.lightsOut;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 24)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);

    _shakeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _shakeController.reset();
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_pulseController);

    _checkeredController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _checkeredAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: Curves.decelerate))
        .animate(_checkeredController);

    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _idleAnimation = Tween<double>(begin: 0.15, end: 0.55)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_idleController);

    // Realistic lights-out: red afterglow fades quickly like phosphor dying
    _lightsOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0, // Start at end = 0.0 opacity so overlay is invisible at launch
    );
    _lightsOutGlowAnimation = Tween<double>(begin: 0.38, end: 0.0)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(_lightsOutController);
  }

  @override
  void dispose() {
    _resetGameTimers();
    _cooldownTimer?.cancel();
    _shakeController.dispose();
    _pulseController.dispose();
    _checkeredController.dispose();
    _idleController.dispose();
    _lightsOutController.dispose();
    _clickPlayer.dispose();
    _sfxPlayer.dispose();
    super.dispose();
  }

  void _resetGameTimers() {
    _sequenceTimer?.cancel();
    _randomDelayTimer?.cancel();
    _stopwatch.reset();
  }

  Future<void> _loadLeaderboard() async {
    final prefs = await SharedPreferences.getInstance();
    final String? scoresJson = prefs.getString(_prefsKey);
    if (scoresJson != null) {
      final List<dynamic> decoded = jsonDecode(scoresJson);
      setState(() {
        _leaderboard = decoded.map((e) => Score.fromJson(e)).toList();
        _leaderboard.sort((a, b) => a.timeMs.compareTo(b.timeMs));
      });
    }
  }

  Future<void> _saveScore(int timeMs) async {
    final prefs = await SharedPreferences.getInstance();
    final newScore = Score(name: _playerName, timeMs: timeMs, date: DateTime.now());
    _leaderboard.add(newScore);
    _leaderboard.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    if (_leaderboard.length > _leaderboardCap) {
      _leaderboard = _leaderboard.take(_leaderboardCap).toList();
    }
    final encoded = jsonEncode(_leaderboard.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
    setState(() {});
  }

  void _startGame() {
    if (_gameState == GameState.starting || _gameState == GameState.waitingForLightsOut) return;

    _checkeredController.reset();
    _idleController.stop();
    setState(() {
      _gameState = GameState.starting;
      _lightsLit = 0;
      _reactionTime = null;
      _isNewPersonalBest = false;
      // Don't reset streak here — only reset on jump start or explicit reset
    });

    _sequenceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _lightsLit++;
      });
      HapticFeedback.lightImpact();
      _clickPlayer.play(AssetSource('sounds/light_on.mp3'));

      if (_lightsLit == 5) {
        timer.cancel();
        setState(() {
          _gameState = GameState.waitingForLightsOut;
        });
        _startRandomDelay();
      }
    });
  }

  void _startRandomDelay() {
    final random = Random();
    final delayMs = _minDelayMs + random.nextInt(_additionalDelayRangeMs);

    _randomDelayTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_gameState == GameState.waitingForLightsOut) {
        setState(() {
          _gameState = GameState.lightsOut;
          _lightsLit = 0;
        });
        HapticFeedback.heavyImpact();
        _sfxPlayer.play(AssetSource('sounds/lights_out.mp3'));
        _pulseController.forward(from: 0.0);
        // Trigger the cinematic red afterglow fade instead of a hard flash
        _lightsOutController.forward(from: 0.0);
        _stopwatch.reset();
        _stopwatch.start();
      }
    });
  }

  void _handleTap() {
    if (_isCooldown) return;

    if (_gameState == GameState.finished || _gameState == GameState.jumpStart) {
      _resetGameTimers();
      _startGame();
      return;
    }

    if (_gameState == GameState.idle) {
      _startGame();
      return;
    }

    if (_gameState == GameState.starting || _gameState == GameState.waitingForLightsOut) {
      _resetGameTimers();
      setState(() {
        _gameState = GameState.jumpStart;
        _lightsLit = 0;
        _isCooldown = true;
        // Jump start BREAKS the streak
        _currentStreak = 0;
      });
      _shakeController.forward();
      HapticFeedback.vibrate();
      _sfxPlayer.play(AssetSource('sounds/jump_start.mp3'));

      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isCooldown = false;
          });
        }
      });
      return;
    }

    if (_gameState == GameState.lightsOut) {
      _stopwatch.stop();
      _sfxPlayer.play(AssetSource('sounds/result.mp3'));
      final elapsed = _stopwatch.elapsedMilliseconds;
      final bool newBest = _personalBestTime == null || elapsed < _personalBestTime!;
      if (newBest) _personalBestTime = elapsed;
      setState(() {
        _reactionTime = elapsed;
        _gameState = GameState.finished;
        _isNewPersonalBest = newBest;
        // Increment streak — any clean reaction counts
        _currentStreak++;
        if (_currentStreak > _bestStreak) _bestStreak = _currentStreak;
        _sessionHistory.add(elapsed);
        if (_sessionHistory.length > _sessionHistoryCap) {
          _sessionHistory.removeAt(0);
        }
      });
      _idleController.repeat(reverse: true);
      if (elapsed < _eliteThresholdMs) {
        _checkeredController.forward(from: 0.0);
      }
      _saveScore(elapsed);
    }
  }

  String _getTier(int timeMs) {
    if (timeMs < _eliteThresholdMs) return "👽 POLE POSITION";
    if (timeMs < _gridThresholdMs) return "🏁 PODIUM FINISH";
    if (timeMs < _rookieThresholdMs) return "🟡 MIDFIELD";
    return "🐌 PIT STOP CREW";
  }

  /// Returns the player's position in the leaderboard (1-indexed).
  /// Returns null if the time is not present in the leaderboard yet.
  int? _getRank(int timeMs) {
    for (int i = 0; i < _leaderboard.length; i++) {
      if (_leaderboard[i].timeMs == timeMs) return i + 1;
    }
    return null;
  }

  Color _getTierColor(int timeMs) {
    if (timeMs < _eliteThresholdMs) return const Color(0xFFB15BFF);
    if (timeMs < _gridThresholdMs) return const Color(0xFF00FF00);
    if (timeMs < _rookieThresholdMs) return const Color(0xFFFFD700);
    return const Color(0xFFE10600);
  }

  /// Milestone label shown at streak thresholds.
  String _getStreakLabel(int streak) {
    if (streak >= 10) return '🔥🔥🔥 MACHINE';
    if (streak >= 5) return '🔥🔥 UNSTOPPABLE';
    if (streak >= 3) return '🔥 ON FIRE';
    return '🔥 x$streak STREAK';
  }

  /// Streak badge color — escalates with milestone.
  Color _getStreakColor(int streak) {
    if (streak >= 10) return const Color(0xFFB15BFF); // purple — legendary
    if (streak >= 5) return const Color(0xFFFF6B00);  // deep orange — on fire
    return const Color(0xFFFFD700);                   // gold — building up
  }

  void _editName() {
    // Fix: dispose the controller to prevent memory leaks
    final TextEditingController controller = TextEditingController(text: _playerName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Color(0xFFE10600), width: 3),
          ),
          title: const Text(
            'DRIVER REGISTRATION',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            cursorColor: const Color(0xFFE10600),
            autofocus: true,
            decoration: const InputDecoration(
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE10600), width: 2)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
              hintText: 'Enter driver name',
              hintStyle: TextStyle(color: Colors.white24),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _playerName = controller.text.trim().isEmpty ? "Driver" : controller.text.trim();
                });
                controller.dispose(); // Fix: properly dispose controller
                Navigator.pop(context);
              },
              child: const Text('CONFIRM', style: TextStyle(color: Color(0xFFE10600), fontWeight: FontWeight.bold)),
            )
          ],
        );
      },
    ).then((_) => controller.dispose()); // Fix: also dispose if dialog dismissed via back button
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: CarbonFiberPainter()),
          ),
          // Racing track perspective — adds depth and atmosphere
          Positioned.fill(
            child: CustomPaint(painter: TrackHorizonPainter()),
          ),
          Positioned.fill(
            child: CustomPaint(painter: GridPainter()),
          ),
          if (_reactionTime != null && _reactionTime! < _eliteThresholdMs && _gameState == GameState.finished)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _checkeredAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: CheckeredFlagPainter(progress: _checkeredAnimation.value),
                  );
                },
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _handleTap(),
            child: Container(
              color: Colors.transparent,
              width: double.infinity,
              height: double.infinity,
              child: AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(sin(_shakeAnimation.value * pi * 4) * 12, 0),
                    child: child,
                  );
                },
                child: RepaintBoundary(child: _buildMainContent()),
              ),
            ),
          ),
          // Cockpit vignette — darkens screen edges for an immersive in-car feel
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.15,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.80),
                    ],
                    stops: const [0.36, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Cinematic red afterglow: fades from 38% opacity red to transparent
          // over 300ms — simulates phosphor decay of the F1 red lights
          AnimatedBuilder(
            animation: _lightsOutGlowAnimation,
            builder: (context, child) {
              if (_lightsOutGlowAnimation.value <= 0.0) {
                return const SizedBox.shrink();
              }
              return Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: const Color(0xFFCC0000)
                        .withValues(alpha: _lightsOutGlowAnimation.value),
                  ),
                ),
              );
            },
          ),
          if (_isLeaderboardOpen)
            Positioned.fill(child: _buildLeaderboardOverlay()),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          // Constrain width so gantry stays centred on wide desktop / web screens.
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildHeader(),
              const Spacer(),
              _buildGantry(),
              const SizedBox(height: 50),
              _buildCenterMessage(),
              const Spacer(),
              _buildHistoryGraph(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedOpacity(
      opacity: _isGameActive ? 0.2 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: _isGameActive,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: SizedBox(
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Left: Driver Profile & Streak
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _editName,
                        child: Transform(
                          transform: Matrix4.skewX(-0.15),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              border: const Border(
                                left: BorderSide(color: Color(0xFFE10600), width: 4),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  offset: const Offset(2, 2),
                                  blurRadius: 4,
                                )
                              ],
                            ),
                            child: Transform(
                              transform: Matrix4.skewX(0.15),
                              child: Row(
                                children: [
                                  const Icon(Icons.sports_motorsports, color: Colors.white70, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    _playerName.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontStyle: FontStyle.italic,
                                      letterSpacing: 1.0,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.edit, color: Colors.white38, size: 12),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_currentStreak >= 2) ...[
                        const SizedBox(width: 6),
                        AnimatedBuilder(
                          animation: _idleAnimation,
                          builder: (context, _) {
                            final streakColor = _getStreakColor(_currentStreak);
                            return Transform(
                              transform: Matrix4.skewX(-0.15),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  border: Border.all(
                                    color: streakColor.withValues(alpha: _idleAnimation.value + 0.45),
                                    width: 2.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: streakColor.withValues(alpha: _idleAnimation.value * 0.6),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Transform(
                                  transform: Matrix4.skewX(0.15),
                                  child: Text(
                                    '🔥 x$_currentStreak',
                                    style: TextStyle(
                                      color: streakColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                // Center: Game Branding
                Align(
                  alignment: Alignment.center,
                  child: Transform(
                    transform: Matrix4.skewX(-0.15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        border: Border.all(
                          color: const Color(0xFFE10600).withValues(alpha: 0.4),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE10600).withValues(alpha: 0.15),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )
                        ],
                      ),
                      child: const Text(
                        'LIGHTS OUT',
                        style: TextStyle(
                          color: Color(0xFFE10600), // F1 Red
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 2.5,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),

                // Right: Leaderboard Button
                Align(
                  alignment: Alignment.centerRight,
                  child: Transform(
                    transform: Matrix4.skewX(-0.15),
                    child: GestureDetector(
                      onTap: () {
                        _resetGameTimers();
                        setState(() {
                          _isLeaderboardOpen = true;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          border: const Border(
                            right: BorderSide(color: Colors.white, width: 3),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              offset: const Offset(-2, 2),
                              blurRadius: 4,
                            )
                          ],
                        ),
                        child: Transform(
                          transform: Matrix4.skewX(0.15),
                          child: const Icon(Icons.leaderboard, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGantry() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 22,
          width: min(430.0, MediaQuery.sizeOf(context).width * 0.92),
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: const Color(0xFF444444), width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 6)),
            ],
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF333333), Color(0xFF111111)],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            bool isOn = index < _lightsLit;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5.0),
              child: _buildLightBox(isOn),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildLightBox(bool isOn) {
    return Container(
      width: min(64.0, MediaQuery.sizeOf(context).width * 0.14),
      height: 195,
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 10,
            offset: Offset(0, 5),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildCircle(isOn),
          _buildCircle(isOn),
        ],
      ),
    );
  }

  Widget _buildCircle(bool isOn) {
    final size = min(50.0, MediaQuery.sizeOf(context).width * 0.12);
    // Idle state: breathe the glow to hint that the gantry is interactive
    final bool isIdle = _gameState == GameState.idle;

    if (isIdle) {
      return AnimatedBuilder(
        animation: _idleAnimation,
        builder: (context, _) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A1A1A),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE10600).withValues(alpha: _idleAnimation.value),
                  blurRadius: 18,
                  spreadRadius: 3,
                ),
              ],
            ),
          );
        },
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOn ? const Color(0xFFE10600) : const Color(0xFF1A1A1A),
        boxShadow: isOn
            ? [
                BoxShadow(
                  color: const Color(0xFFE10600).withValues(alpha: 0.8),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.6),
                  blurRadius: 4,
                  spreadRadius: 0,
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 4,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                  blurStyle: BlurStyle.inner,
                )
              ],
      ),
    );
  }

  Widget _buildCenterMessage() {
    if (_gameState == GameState.finished) {
      return _buildPitBoardResult(_reactionTime ?? 0);
    }

    String mainText = "";
    String subText = "";
    Color textColor = Colors.white;

    switch (_gameState) {
      case GameState.idle:
        mainText = "TAP TO START";
        subText = "React as fast as possible when lights go out!";
        textColor = Colors.white70;
        break;
      case GameState.starting:
        mainText = "PREPARE...";
        textColor = Colors.redAccent;
        break;
      case GameState.waitingForLightsOut:
        mainText = "HOLD...";
        textColor = Colors.red;
        break;
      case GameState.lightsOut:
        mainText = "";
        textColor = const Color(0xFF00FF00);
        break;
      case GameState.jumpStart:
        mainText = "FALSE START!";
        subText = "Tap anywhere to try again.";
        textColor = Colors.red;
        break;
      case GameState.finished:
        // Handled above
        break;
    }

    final column = Column(
      children: [
        Text(
          mainText,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _gameState == GameState.finished ||
                    _gameState == GameState.lightsOut ||
                    _gameState == GameState.jumpStart
                ? 48
                : 32,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            color: textColor,
            shadows: [
              if (_gameState == GameState.lightsOut)
                Shadow(
                  color: const Color(0xFF00FF00).withValues(alpha: 0.5),
                  blurRadius: 20,
                )
            ],
          ),
        ),
        if (subText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.white54,
            ),
          ),
        ]
      ],
    );

    if (_gameState == GameState.lightsOut) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        ),
        child: column,
      );
    }

    // Idle state: wrap the CTA in a pulsing red glow ring to signal interactivity
    if (_gameState == GameState.idle) {
      return AnimatedBuilder(
        animation: _idleAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: const Color(0xFFE10600).withValues(alpha: _idleAnimation.value * 0.85),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE10600).withValues(alpha: _idleAnimation.value * 0.22),
                  blurRadius: 35,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: child,
          );
        },
        child: column,
      );
    }

    return column;
  }

  Widget _buildPitBoardResult(int timeMs) {
    final tierColor = _getTierColor(timeMs);
    final tierText = _getTier(timeMs);
    
    return Transform(
      transform: Matrix4.skewX(-0.12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          border: Border.all(color: tierColor, width: 3),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              offset: const Offset(6, 6),
              blurRadius: 0,
            )
          ],
        ),
        child: Transform(
          transform: Matrix4.skewX(0.12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "REACTION TIME",
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(width: 40),
                  Builder(builder: (context) {
                    // Fix: compute actual leaderboard rank instead of hardcoded P1
                    final rank = _getRank(timeMs);
                    return Text(
                      rank != null ? "P$rank" : "--",
                      style: TextStyle(
                        color: tierColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "${(timeMs / 1000).toStringAsFixed(3)} s",
                style: const TextStyle(
                  color: Colors.yellowAccent,
                  fontSize: 46,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "$timeMs ms",
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10.0),
                child: SizedBox(
                  width: 150,
                  child: Divider(color: Colors.white12, height: 1),
                ),
              ),
              Text(
                tierText,
                style: TextStyle(
                  color: tierColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 1.2,
                ),
              ),
              // Personal best badge — shown when the player beats their session record
              if (_isNewPersonalBest) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    ),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Text(
                    "🏆  NEW PERSONAL BEST!",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
              // Streak badge — shown when player is on a streak of 2+
              if (_currentStreak >= 2) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    border: Border.all(
                      color: _getStreakColor(_currentStreak),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: _getStreakColor(_currentStreak).withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Text(
                    _getStreakLabel(_currentStreak),
                    style: TextStyle(
                      color: _getStreakColor(_currentStreak),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                "TAP ANYWHERE TO RETRY",
                style: TextStyle(
                  color: Colors.white30,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryGraph() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 30.0),
      child: Column(
        children: [
          Opacity(
            opacity: 0.12,
            child: Container(
              height: 35,
              margin: const EdgeInsets.only(bottom: 12),
              child: Image.asset(
                'assets/images/formula_car_silhouette.png',
                fit: BoxFit.contain,
                colorBlendMode: BlendMode.screen,
                color: Colors.white,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 8, height: 8, color: const Color(0xFFE10600)),
              const SizedBox(width: 8),
              const Text(
                "LIVE TELEMETRY",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            height: 80,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: _sessionHistory.length > 1
                ? CustomPaint(
                    painter: GraphPainter(_sessionHistory),
                  )
                : const Center(
                    child: Text(
                      "AWAITING TELEMETRY DATA...",
                      style: TextStyle(color: Colors.white24, fontSize: 14, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardOverlay() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        color: const Color(0xFF0D0D0D).withValues(alpha: 0.98),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Transform(
                transform: Matrix4.skewX(-0.15),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    border: Border(left: BorderSide(color: Color(0xFFE10600), width: 6)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Transform(
                        transform: Matrix4.skewX(0.15),
                        child: const Text(
                          "GLOBAL STANDINGS",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      Transform(
                        transform: Matrix4.skewX(0.15),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isLeaderboardOpen = false;
                              _gameState = GameState.idle;
                            });
                          },
                          child: const Icon(Icons.close, color: Colors.white, size: 28),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _leaderboard.isEmpty
                    ? const Center(
                        child: Text("NO TELEMETRY RECORDED", style: TextStyle(color: Colors.white54, fontSize: 18, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
                      )
                    : ListView.builder(
                        itemCount: _leaderboard.length,
                        itemBuilder: (context, index) {
                          final score = _leaderboard[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              border: Border(left: BorderSide(color: _getTierColor(score.timeMs), width: 4)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Text(
                                "P${index + 1}",
                                style: const TextStyle(color: Colors.white54, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic),
                              ),
                              title: Text(
                                score.name.toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                              ),
                              subtitle: Text(
                                _getTier(score.timeMs),
                                style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              trailing: Text(
                                "${score.timeMs} ms",
                                style: TextStyle(
                                  color: _getTierColor(score.timeMs),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
