class ChatEntry {
  final DateTime time;
  final String question;
  final String answer;
  final bool isError;

  const ChatEntry({
    required this.time,
    required this.question,
    required this.answer,
    required this.isError,
  });

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'question': question,
        'answer': answer,
        'is_error': isError,
      };

  factory ChatEntry.fromJson(Map<String, dynamic> json) => ChatEntry(
        time:
            DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
        question: json['question'] as String? ?? '',
        answer: json['answer'] as String? ?? '',
        isError: json['is_error'] as bool? ?? false,
      );
}
