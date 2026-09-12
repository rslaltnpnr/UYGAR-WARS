/// Bir makronun tek adimi - "URL ac", "medya komutu" ya da "guc komutu"
/// turlerinden biri. [value] adimin turune gore anlam degistirir: open_url
/// icin acilacak baglanti, media/power icin RemoteControlService'in
/// bekledigi aksiyon adi (orn. 'play_pause', 'lock').
class MacroStep {
  final String type;
  final String value;

  const MacroStep({required this.type, required this.value});

  Map<String, dynamic> toJson() => {'type': type, 'value': value};

  factory MacroStep.fromJson(Map<String, dynamic> json) => MacroStep(
        type: json['type'] as String? ?? '',
        value: json['value'] as String? ?? '',
      );
}

/// Kullanicinin tanimladigi, birden fazla komutu (baglanti acma, medya,
/// guc) tek dokunusla sirayla calistiran adimlar dizisi - orn. "Calisma
/// Modu" makrosu hem bir muzik linki acabilir hem de sesi kisabilir.
class CommandMacro {
  final String id;
  final String name;
  final List<MacroStep> steps;

  const CommandMacro({
    required this.id,
    required this.name,
    required this.steps,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory CommandMacro.fromJson(Map<String, dynamic> json) => CommandMacro(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        steps: (json['steps'] as List<dynamic>? ?? [])
            .map((e) => MacroStep.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
