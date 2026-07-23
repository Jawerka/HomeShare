import 'dart:io';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:homeshare_p2p/homeshare_p2p.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpA;
  late Directory tmpB;

  setUp(() async {
    tmpA = await Directory.systemTemp.createTemp('hs-a-');
    tmpB = await Directory.systemTemp.createTemp('hs-b-');
  });

  tearDown(() async {
    if (await tmpA.exists()) await tmpA.delete(recursive: true);
    if (await tmpB.exists()) await tmpB.delete(recursive: true);
  });

  test('pairing + single file transfer e2e', () async {
    final dataA = Directory('${tmpA.path}/data');
    final dataB = Directory('${tmpB.path}/data');
    final inboxB = Directory('${tmpB.path}/inbox');

    final idA = await DeviceIdentity.loadOrCreate(
      dataDir: dataA,
      displayName: 'Alice',
    );
    final idB = await DeviceIdentity.loadOrCreate(
      dataDir: dataB,
      displayName: 'Bob',
    );
    final tokensA = await TokenStore.open(dataA);
    final tokensB = await TokenStore.open(dataB);

    final configA = AppConfig(
      displayName: 'Alice',
      inboxDir: '${tmpA.path}/inbox',
      dataDir: dataA.path,
      p2pPort: 0,
    );
    final configB = AppConfig(
      displayName: 'Bob',
      inboxDir: inboxB.path,
      dataDir: dataB.path,
      p2pPort: 0,
    );

    final pairingB = PairingService(
      identity: idB,
      config: configB,
      tokenStore: tokensB,
    );
    final serverB = PeerServer(
      identity: idB,
      config: configB,
      tokenStore: tokensB,
      inboxWriter: InboxWriter(inboxDir: inboxB),
      pairing: pairingB,
    );
    await serverB.start(port: 0);
    final port = serverB.boundPort!;

    final pairingA = PairingService(
      identity: idA,
      config: configA,
      tokenStore: tokensA,
    );
    final offer = pairingB.getOrCreateOffer();
    final peer = await pairingA.confirmAsGuest(
      host: '127.0.0.1',
      port: port,
      pin: offer.pin.value,
    );
    expect(peer.peerId.value, idB.peerId);
    expect(configB.findPeer(idA.peerId), isNotNull);
    expect(tokensA.get(idB.peerId), isNotNull);
    expect(tokensB.get(idA.peerId), isNotNull);

    // Update peer host for transfer.
    final trustedB = configA.findPeer(idB.peerId)!.copyWith(
          host: '127.0.0.1',
          port: port,
          online: true,
        );
    await configA.upsertPeer(trustedB);

    final src = File('${tmpA.path}/hello.bin');
    await src.writeAsBytes(List<int>.generate(5000, (i) => i % 256));

    final client = TransferClient(identity: idA, tokenStore: tokensA);
    await client.sendFile(
      peer: trustedB,
      transferId: 'e2e-file-1',
      file: src,
    );

    final dest = File('${inboxB.path}/hello.bin');
    expect(await dest.exists(), isTrue);
    expect(await dest.length(), 5000);
    expect(
      await Sha256Stream.hashFile(dest),
      await Sha256Stream.hashFile(src),
    );

    client.close();
    await serverB.stop();
  });

  test('directory transfer e2e', () async {
    final dataA = Directory('${tmpA.path}/data');
    final dataB = Directory('${tmpB.path}/data');
    final inboxB = Directory('${tmpB.path}/inbox');

    final idA = await DeviceIdentity.loadOrCreate(
      dataDir: dataA,
      displayName: 'Alice',
    );
    final idB = await DeviceIdentity.loadOrCreate(
      dataDir: dataB,
      displayName: 'Bob',
    );
    final tokensA = await TokenStore.open(dataA);
    final tokensB = await TokenStore.open(dataB);

    final configA = AppConfig(
      displayName: 'Alice',
      inboxDir: '${tmpA.path}/inbox',
      dataDir: dataA.path,
    );
    final configB = AppConfig(
      displayName: 'Bob',
      inboxDir: inboxB.path,
      dataDir: dataB.path,
    );

    // Pre-trust both sides (simulate completed pairing).
    final token = TokenStore.generateToken();
    await tokensA.put(idB.peerId, token);
    await tokensB.put(idA.peerId, token);
    await configA.upsertPeer(
      TrustedPeer(
        peerId: PeerId(idB.peerId),
        displayName: 'Bob',
        host: '127.0.0.1',
        signingPublicKey: idB.publicKeyHex,
      ),
    );
    await configB.upsertPeer(
      TrustedPeer(
        peerId: PeerId(idA.peerId),
        displayName: 'Alice',
        signingPublicKey: idA.publicKeyHex,
      ),
    );

    final pairingB = PairingService(
      identity: idB,
      config: configB,
      tokenStore: tokensB,
    );
    final serverB = PeerServer(
      identity: idB,
      config: configB,
      tokenStore: tokensB,
      inboxWriter: InboxWriter(inboxDir: inboxB),
      pairing: pairingB,
    );
    await serverB.start(port: 0);
    final port = serverB.boundPort!;

    final dir = Directory('${tmpA.path}/folder')..createSync();
    await File('${dir.path}/a.txt').writeAsString('aaa');
    await Directory('${dir.path}/sub').create();
    await File('${dir.path}/sub/b.txt').writeAsString('bbbb');

    final peer = configA.findPeer(idB.peerId)!.copyWith(port: port);
    await configA.upsertPeer(peer);

    final client = TransferClient(identity: idA, tokenStore: tokensA);
    await client.sendDirectory(
      peer: peer,
      transferId: 'e2e-dir-1',
      directory: dir,
    );

    final saved = Directory('${inboxB.path}/folder');
    expect(await saved.exists(), isTrue);
    expect(await File('${saved.path}/a.txt').readAsString(), 'aaa');
    expect(await File('${saved.path}/sub/b.txt').readAsString(), 'bbbb');

    client.close();
    await serverB.stop();
  });

  test('disk_full rejects offer', () async {
    final dataB = Directory('${tmpB.path}/data');
    final inboxB = Directory('${tmpB.path}/inbox')..createSync(recursive: true);
    final idB = await DeviceIdentity.loadOrCreate(
      dataDir: dataB,
      displayName: 'Bob',
    );
    final tokensB = await TokenStore.open(dataB);
    final configB = AppConfig(
      displayName: 'Bob',
      inboxDir: inboxB.path,
      dataDir: dataB.path,
    );
    final token = TokenStore.generateToken();
    final idA = 'alice-id';
    await tokensB.put(idA, token);
    await configB.upsertPeer(
      TrustedPeer(peerId: PeerId(idA), displayName: 'Alice'),
    );

    final serverB = PeerServer(
      identity: idB,
      config: configB,
      tokenStore: tokensB,
      inboxWriter: InboxWriter(inboxDir: inboxB),
      pairing: PairingService(
        identity: idB,
        config: configB,
        tokenStore: tokensB,
      ),
    );
    await serverB.start(port: 0);

    // Monkey-patch by sending huge size — DiskSpace may still allow;
    // instead verify path_invalid on bad manifest path.
    final client = HttpClient();
    final req = await client.postUrl(
      Uri.parse(
        'http://127.0.0.1:${serverB.boundPort}'
        '${HomeShareProtocol.pathPrefix}/transfer/offer',
      ),
    );
    req.headers.set(HomeShareProtocol.headerPeerId, idA);
    req.headers.set(HomeShareProtocol.headerAuthToken, token);
    req.headers.contentType = ContentType.json;
    req.write(
      '{"transfer_id":"x","name":"bad","kind":"dir","size":10,'
      '"file_count":1,"manifest":[{"path":"../evil","size":10}]}',
    );
    final res = await req.close();
    expect(res.statusCode, 400);
    client.close(force: true);
    await serverB.stop();
  });

  test('auth reject and disk_full on offer', () async {
    final dataB = Directory('${tmpB.path}/data');
    final inboxB = Directory('${tmpB.path}/inbox')..createSync(recursive: true);
    final idB = await DeviceIdentity.loadOrCreate(
      dataDir: dataB,
      displayName: 'Bob',
    );
    final tokensB = await TokenStore.open(dataB);
    final configB = AppConfig(
      displayName: 'Bob',
      inboxDir: inboxB.path,
      dataDir: dataB.path,
    );
    final token = TokenStore.generateToken();
    const idA = 'alice-id';
    await tokensB.put(idA, token);
    await configB.upsertPeer(
      TrustedPeer(peerId: PeerId(idA), displayName: 'Alice'),
    );

    final serverB = PeerServer(
      identity: idB,
      config: configB,
      tokenStore: tokensB,
      inboxWriter: InboxWriter(inboxDir: inboxB),
      pairing: PairingService(
        identity: idB,
        config: configB,
        tokenStore: tokensB,
      ),
      diskSpaceForPath: (path) async => const DiskSpaceReport(
        path: '/',
        freeBytes: 1024,
        totalBytes: 2048,
      ),
    );
    await serverB.start(port: 0);
    final port = serverB.boundPort!;
    final client = HttpClient();

    Future<int> offer({String? authToken, int size = 100}) async {
      final req = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:$port'
          '${HomeShareProtocol.pathPrefix}/transfer/offer',
        ),
      );
      req.headers.set(HomeShareProtocol.headerPeerId, idA);
      if (authToken != null) {
        req.headers.set(HomeShareProtocol.headerAuthToken, authToken);
      }
      req.headers.contentType = ContentType.json;
      req.write(
        '{"transfer_id":"auth-disk","name":"x.bin","kind":"file","size":$size,'
        '"file_count":1}',
      );
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    }

    expect(await offer(), 401);
    expect(await offer(authToken: 'wrong'), 401);
    expect(await offer(authToken: token, size: 10 * 1024 * 1024), 507);

    client.close(force: true);
    await serverB.stop();
  });

  test('file transfer resume after partial upload', () async {
    final dataA = Directory('${tmpA.path}/data');
    final dataB = Directory('${tmpB.path}/data');
    final inboxB = Directory('${tmpB.path}/inbox');

    final idA = await DeviceIdentity.loadOrCreate(
      dataDir: dataA,
      displayName: 'Alice',
    );
    final idB = await DeviceIdentity.loadOrCreate(
      dataDir: dataB,
      displayName: 'Bob',
    );
    final tokensA = await TokenStore.open(dataA);
    final tokensB = await TokenStore.open(dataB);
    final token = TokenStore.generateToken();
    await tokensA.put(idB.peerId, token);
    await tokensB.put(idA.peerId, token);

    final configA = AppConfig(
      displayName: 'Alice',
      inboxDir: '${tmpA.path}/inbox',
      dataDir: dataA.path,
    );
    final configB = AppConfig(
      displayName: 'Bob',
      inboxDir: inboxB.path,
      dataDir: dataB.path,
    );
    await configA.upsertPeer(
      TrustedPeer(
        peerId: PeerId(idB.peerId),
        displayName: 'Bob',
        host: '127.0.0.1',
        signingPublicKey: idB.publicKeyHex,
      ),
    );
    await configB.upsertPeer(
      TrustedPeer(
        peerId: PeerId(idA.peerId),
        displayName: 'Alice',
        signingPublicKey: idA.publicKeyHex,
      ),
    );

    final writer = InboxWriter(inboxDir: inboxB);
    final serverB = PeerServer(
      identity: idB,
      config: configB,
      tokenStore: tokensB,
      inboxWriter: writer,
      pairing: PairingService(
        identity: idB,
        config: configB,
        tokenStore: tokensB,
      ),
    );
    await serverB.start(port: 0);
    final port = serverB.boundPort!;

    final src = File('${tmpA.path}/resume.bin');
    final bytes = List<int>.generate(8000, (i) => i % 256);
    await src.writeAsBytes(bytes);

    // Simulate interrupted first half.
    await writer.writeChunk(
      transferId: 'e2e-resume-1',
      relativePath: 'payload',
      offset: 0,
      bytes: bytes.sublist(0, 3000),
    );

    final peer = configA.findPeer(idB.peerId)!.copyWith(port: port);
    await configA.upsertPeer(peer);

    final client = TransferClient(identity: idA, tokenStore: tokensA);
    await client.sendFile(
      peer: peer,
      transferId: 'e2e-resume-1',
      file: src,
    );

    final dest = File('${inboxB.path}/resume.bin');
    expect(await dest.exists(), isTrue);
    expect(await dest.length(), 8000);
    expect(
      await Sha256Stream.hashFile(dest),
      await Sha256Stream.hashFile(src),
    );

    client.close();
    await serverB.stop();
  });

  test('offer rejects disk probe failure', () async {
    final dataB = Directory('${tmpB.path}/data');
    final inboxB = Directory('${tmpB.path}/inbox')..createSync(recursive: true);
    final idB = await DeviceIdentity.loadOrCreate(
      dataDir: dataB,
      displayName: 'Bob',
    );
    final tokensB = await TokenStore.open(dataB);
    final configB = AppConfig(
      displayName: 'Bob',
      inboxDir: inboxB.path,
      dataDir: dataB.path,
    );
    const idA = 'alice-id';
    final token = TokenStore.generateToken();
    await tokensB.put(idA, token);
    await configB.upsertPeer(
      TrustedPeer(peerId: PeerId(idA), displayName: 'Alice'),
    );

    final serverB = PeerServer(
      identity: idB,
      config: configB,
      tokenStore: tokensB,
      inboxWriter: InboxWriter(inboxDir: inboxB),
      pairing: PairingService(
        identity: idB,
        config: configB,
        tokenStore: tokensB,
      ),
      diskSpaceForPath: (path) async => DiskSpaceReport.unknown(path),
    );
    await serverB.start(port: 0);
    final client = HttpClient();
    final req = await client.postUrl(
      Uri.parse(
        'http://127.0.0.1:${serverB.boundPort}'
        '${HomeShareProtocol.pathPrefix}/transfer/offer',
      ),
    );
    req.headers.set(HomeShareProtocol.headerPeerId, idA);
    req.headers.set(HomeShareProtocol.headerAuthToken, token);
    req.headers.contentType = ContentType.json;
    req.write(
      '{"transfer_id":"probe-fail","name":"x.bin","kind":"file","size":100,'
      '"file_count":1}',
    );
    final res = await req.close();
    expect(res.statusCode, 507);
    client.close(force: true);
    await serverB.stop();
  });

  test('offer rejects size and manifest limits', () async {
    final dataB = Directory('${tmpB.path}/data');
    final inboxB = Directory('${tmpB.path}/inbox')..createSync(recursive: true);
    final idB = await DeviceIdentity.loadOrCreate(
      dataDir: dataB,
      displayName: 'Bob',
    );
    final tokensB = await TokenStore.open(dataB);
    final configB = AppConfig(
      displayName: 'Bob',
      inboxDir: inboxB.path,
      dataDir: dataB.path,
      maxTransferBytes: 1024,
      maxManifestEntries: 2,
    );
    const idA = 'alice-id';
    final token = TokenStore.generateToken();
    await tokensB.put(idA, token);
    await configB.upsertPeer(
      TrustedPeer(peerId: PeerId(idA), displayName: 'Alice'),
    );

    final serverB = PeerServer(
      identity: idB,
      config: configB,
      tokenStore: tokensB,
      inboxWriter: InboxWriter(inboxDir: inboxB),
      pairing: PairingService(
        identity: idB,
        config: configB,
        tokenStore: tokensB,
      ),
      diskSpaceForPath: (path) async => const DiskSpaceReport(
        path: '/',
        freeBytes: 1 << 30,
        totalBytes: 1 << 31,
      ),
    );
    await serverB.start(port: 0);
    final port = serverB.boundPort!;
    final client = HttpClient();

    Future<int> offerBody(String body) async {
      final req = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:$port${HomeShareProtocol.pathPrefix}/transfer/offer',
        ),
      );
      req.headers.set(HomeShareProtocol.headerPeerId, idA);
      req.headers.set(HomeShareProtocol.headerAuthToken, token);
      req.headers.contentType = ContentType.json;
      req.write(body);
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    }

    expect(
      await offerBody(
        '{"transfer_id":"big","name":"x.bin","kind":"file","size":2048,"file_count":1}',
      ),
      413,
    );
    expect(
      await offerBody(
        '{"transfer_id":"many","name":"dir","kind":"dir","size":10,"file_count":3,'
        '"manifest":[{"path":"a","size":1},{"path":"b","size":1},{"path":"c","size":1}]}',
      ),
      413,
    );

    client.close(force: true);
    await serverB.stop();
  });

  test('blob PUT rejects concurrent write', () async {
    final dataB = Directory('${tmpB.path}/data');
    final inboxB = Directory('${tmpB.path}/inbox')..createSync(recursive: true);
    final idB = await DeviceIdentity.loadOrCreate(
      dataDir: dataB,
      displayName: 'Bob',
    );
    final tokensB = await TokenStore.open(dataB);
    final configB = AppConfig(
      displayName: 'Bob',
      inboxDir: inboxB.path,
      dataDir: dataB.path,
    );
    const idA = 'alice-id';
    final token = TokenStore.generateToken();
    await tokensB.put(idA, token);
    await configB.upsertPeer(
      TrustedPeer(peerId: PeerId(idA), displayName: 'Alice'),
    );

    final writer = InboxWriter(inboxDir: inboxB);
    final serverB = PeerServer(
      identity: idB,
      config: configB,
      tokenStore: tokensB,
      inboxWriter: writer,
      pairing: PairingService(
        identity: idB,
        config: configB,
        tokenStore: tokensB,
      ),
    );
    await serverB.start(port: 0);
    final port = serverB.boundPort!;
    final client = HttpClient();

    final offerReq = await client.postUrl(
      Uri.parse(
        'http://127.0.0.1:$port${HomeShareProtocol.pathPrefix}/transfer/offer',
      ),
    );
    offerReq.headers.set(HomeShareProtocol.headerPeerId, idA);
    offerReq.headers.set(HomeShareProtocol.headerAuthToken, token);
    offerReq.headers.contentType = ContentType.json;
    offerReq.write(
      '{"transfer_id":"conflict-1","name":"x.bin","kind":"file","size":100,'
      '"file_count":1}',
    );
    final offerRes = await offerReq.close();
    expect(offerRes.statusCode, 200);
    await offerRes.drain<void>();

    Future<int> blobPut() async {
      final req = await client.putUrl(
        Uri.parse(
          'http://127.0.0.1:$port'
          '${HomeShareProtocol.pathPrefix}/transfer/conflict-1/blob',
        ),
      );
      req.headers.set(HomeShareProtocol.headerPeerId, idA);
      req.headers.set(HomeShareProtocol.headerAuthToken, token);
      req.headers.set(HomeShareProtocol.headerUploadOffset, '0');
      req.add([1, 2, 3]);
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    }

    final hold = writer.openWrite(
      transferId: 'conflict-1',
      relativePath: 'payload',
      offset: 0,
    );
    expect(await blobPut(), 409);
    final session = await hold;
    await session.close();

    client.close(force: true);
    await serverB.stop();
  });
}
