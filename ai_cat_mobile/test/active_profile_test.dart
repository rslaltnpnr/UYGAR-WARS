import 'package:ai_cat_mobile/models/remote_profile.dart';
import 'package:ai_cat_mobile/services/active_profile.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteProfile _profile(String id) => RemoteProfile(
      id: id,
      name: id,
      ip: '1.2.3.4',
      port: 8765,
      pin: '000000',
      certFingerprint: '',
    );

void main() {
  group('resolveActiveProfile', () {
    test('bos listede null doner', () {
      expect(resolveActiveProfile([], 'x'), isNull);
    });

    test('eslesen id bulunursa o profil doner', () {
      final profiles = [_profile('a'), _profile('b')];
      expect(resolveActiveProfile(profiles, 'b')?.id, 'b');
    });

    test('eslesme yoksa ilk profile duser', () {
      final profiles = [_profile('a'), _profile('b')];
      expect(resolveActiveProfile(profiles, 'olmayan-id')?.id, 'a');
    });

    test('activeId null olsa da ilk profile duser', () {
      final profiles = [_profile('a'), _profile('b')];
      expect(resolveActiveProfile(profiles, null)?.id, 'a');
    });
  });
}
