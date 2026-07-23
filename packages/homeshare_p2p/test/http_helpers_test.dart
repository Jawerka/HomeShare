import 'package:homeshare_p2p/homeshare_p2p.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('throwIfOfferFailed maps 507/401/403', () {
    expect(
      () => throwIfOfferFailed(http.Response('full', 507)),
      throwsA(
        isA<HomeShareException>().having((e) => e.code, 'code', 'disk_full'),
      ),
    );
    expect(
      () => throwIfOfferFailed(http.Response('nope', 401)),
      throwsA(
        isA<HomeShareException>()
            .having((e) => e.code, 'code', 'auth_required'),
      ),
    );
    expect(
      () => throwIfOfferFailed(http.Response('nope', 403)),
      throwsA(
        isA<HomeShareException>()
            .having((e) => e.code, 'code', 'auth_required'),
      ),
    );
  });

  test('throwIfOfferFailed returns body on 200', () {
    final map = throwIfOfferFailed(
      http.Response('{"resume_offset":12,"status":"ready"}', 200),
    );
    expect(map['resume_offset'], 12);
  });
}
