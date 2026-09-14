import 'package:ai_cat_mobile/services/voice_agent_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAgentAction', () {
    test('gecerli JSON dogru ayristirilir', () {
      final action = parseAgentAction(
        '{"thought":"Tıklıyorum","type":"click","x":0.5,"y":0.5,"risky":false}',
      );
      expect(action, isNotNull);
      expect(action!['type'], 'click');
      expect(action['x'], 0.5);
    });

    test('```json bloguna sarilmis yaniti temizleyip ayristirir', () {
      final action = parseAgentAction(
        '```json\n{"thought":"ok","type":"done","risky":false}\n```',
      );
      expect(action, isNotNull);
      expect(action!['type'], 'done');
    });

    test('bozuk JSON icin null doner', () {
      expect(parseAgentAction('bu json degil'), isNull);
    });

    test('taninmayan "type" degeri icin null doner', () {
      expect(
        parseAgentAction('{"thought":"x","type":"delete_everything"}'),
        isNull,
      );
    });

    test('JSON dizisi (liste) icin null doner - nesne bekleniyor', () {
      expect(parseAgentAction('[{"type":"click"}]'), isNull);
    });

    test('"type" alani eksikse null doner', () {
      expect(parseAgentAction('{"thought":"x"}'), isNull);
    });
  });

  group('isRiskyAction', () {
    test('modelin risky=true isaretledigi eylem riskli sayilir', () {
      expect(isRiskyAction({'type': 'click', 'risky': true}), isTrue);
    });

    test('risky=false ama metninde riskli kelime gecen eylem yine de riskli sayilir', () {
      // Modelin kendi degerlendirmesi tek basina guvenilmez - savunma
      // katmani bu durumda devreye girer.
      expect(
        isRiskyAction({
          'type': 'type',
          'risky': false,
          'thought': 'E-postayı gönderiyorum',
        }),
        isTrue,
      );
    });

    test('hicbir riskli isaret/kelime yoksa riskli sayilmaz', () {
      expect(
        isRiskyAction({
          'type': 'click',
          'risky': false,
          'thought': 'Arama kutusuna tıklıyorum',
        }),
        isFalse,
      );
    });

    test('"risky" alani hic yoksa varsayilan false kabul edilir', () {
      expect(
        isRiskyAction({'type': 'click', 'thought': 'Sayfayı kaydırıyorum'}),
        isFalse,
      );
    });

    test('satın alma/silme gibi Turkce anahtar kelimeler yakalanir', () {
      expect(
        isRiskyAction({'type': 'click', 'thought': 'Ürünü satın alıyorum'}),
        isTrue,
      );
      expect(
        isRiskyAction({'type': 'click', 'thought': 'Dosyayı siliyorum'}),
        isTrue,
      );
    });
  });

  group('describeAgentAction', () {
    test('thought varsa oncelikli olarak onu doner', () {
      expect(
        describeAgentAction({'type': 'click', 'thought': 'Butona tıklandı'}),
        'Butona tıklandı',
      );
    });

    test('thought yoksa turune gore varsayilan bir aciklama uretir', () {
      expect(
        describeAgentAction({'type': 'type', 'text': 'merhaba'}),
        '"merhaba" yazıldı.',
      );
    });
  });
}
