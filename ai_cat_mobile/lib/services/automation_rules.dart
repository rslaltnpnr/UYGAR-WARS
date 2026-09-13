/// Masaustu uygulamasindaki AUTOMATION_TRIGGER_LABELS/
/// AUTOMATION_ACTION_LABELS ile ayni anahtar->etiket eslemeleri - kural
/// bicimi (bkz. main.py'deki yorum) ikisi arasinda paylasilir:
/// {"id", "name", "trigger_type", "trigger_value", "action_type",
///  "action_value", "enabled", "last_fired"}.
const Map<String, String> automationTriggerLabels = {
  'time_daily': 'Her gun belirli bir saatte',
  'idle_minutes': 'N dakika hareketsiz kalinca',
};

const Map<String, String> automationActionLabels = {
  'lock': 'Bilgisayari kilitle',
  'sleep': 'Uyku moduna al',
  'notify': 'Bildirim goster',
  'open_url': 'Bir baglanti ac',
};

/// [rule] icin tek satirlik okunabilir bir aciklama uretir - main.py'deki
/// describe_automation_rule ile ayni bicimde. Bu ekran salt-okunur oldugu
/// icin (kurallar yalnizca masaustunde duzenlenir) bu, telefonda goruntulenen
/// tek temsil.
String describeAutomationRule(Map<String, dynamic> rule) {
  final triggerType = rule['trigger_type'] as String?;
  final triggerLabel = automationTriggerLabels[triggerType] ?? triggerType ?? '?';
  final triggerValue = rule['trigger_value'];
  final triggerDesc = triggerValue == null || triggerValue.toString().isEmpty
      ? triggerLabel
      : '$triggerLabel ($triggerValue)';

  final actionType = rule['action_type'] as String?;
  final actionLabel = automationActionLabels[actionType] ?? actionType ?? '?';
  final actionValue = rule['action_value'];
  final actionDesc = actionValue == null || actionValue.toString().isEmpty
      ? actionLabel
      : '$actionLabel: $actionValue';

  final name = rule['name'] as String? ?? '';
  final suffix = (rule['enabled'] as bool? ?? true) ? '' : ' [devre disi]';
  return '"$name" - $triggerDesc -> $actionDesc$suffix';
}
