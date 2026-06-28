enum GameState { idle, preStart, starting, waitingForLightsOut, lightsOut, jumpStart, finished }

class Score {
  final String name;
  final int timeMs;
  final DateTime date;

  Score({required this.name, required this.timeMs, required this.date});

  Map<String, dynamic> toJson() => {
        'name': name,
        'timeMs': timeMs,
        'date': date.toIso8601String(),
      };

  factory Score.fromJson(Map<String, dynamic> json) => Score(
        name: json['name'],
        timeMs: json['timeMs'],
        date: DateTime.parse(json['date']),
      );
}
