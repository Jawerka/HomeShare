import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'errors.dart';

/// Shelf JSON helpers shared by PeerServer handlers.
Response jsonOk(Object body, {int status = 200}) => Response(
      status,
      body: body is String ? body : jsonEncode(body),
      headers: const {'content-type': 'application/json'},
    );

Response jsonError(
  String code,
  String message, {
  int status = 400,
  Map<String, Object?> extra = const {},
}) =>
    Response(
      status,
      body: jsonEncode({'error': code, 'message': message, ...extra}),
      headers: const {'content-type': 'application/json'},
    );

/// Maps offer HTTP status to [HomeShareException]. Returns body map on 200.
Map<String, dynamic> throwIfOfferFailed(http.Response offerRes) {
  if (offerRes.statusCode == 507) {
    throw HomeShareException.diskFull(offerRes.body);
  }
  if (offerRes.statusCode == 401 || offerRes.statusCode == 403) {
    throw HomeShareException.authRequired(offerRes.body);
  }
  if (offerRes.statusCode != 200) {
    throw HomeShareException(
      'offer_failed',
      offerRes.body,
      statusCode: offerRes.statusCode,
    );
  }
  if (offerRes.body.isEmpty) return {};
  return jsonDecode(offerRes.body) as Map<String, dynamic>;
}
