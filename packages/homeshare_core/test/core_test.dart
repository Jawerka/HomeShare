import 'dart:io';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hs-core-');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('PathSanitize rejects traversal', () {
    expect(() => PathSanitize.sanitizeRelative('../etc/passwd'),
        throwsA(isA<PathSanitizeException>()));
    expect(() => PathSanitize.sanitizeRelative('/abs'),
        throwsA(isA<PathSanitizeException>()));
    expect(PathSanitize.sanitizeRelative('a/b/c.txt'), 'a/b/c.txt');
  });

  test('Sha256Stream hashes file', () async {
    final f = File('${tmp.path}/x.bin');
    await f.writeAsBytes(List<int>.generate(1000, (i) => i % 256));
    final h1 = await Sha256Stream.hashFile(f);
    final h2 = await Sha256Stream.hashFile(f);
    expect(h1, h2);
    expect(h1.length, 64);
  });

  test('Outbox enqueue persist and ack', () async {
    final q = await OutboxQueue.open(tmp);
    final job = await q.enqueue(
      id: 't1',
      peerId: const PeerId('p1'),
      direction: TransferDirection.send,
      kind: TransferKind.file,
      name: 'a.txt',
      totalBytes: 10,
      localPath: '/tmp/a.txt',
    );
    expect(job.state, TransferState.pending);
    await q.update('t1', transferredBytes: 5, state: TransferState.transferring);
    expect(q.get('t1')!.progressPercent, 50);
    await q.ackCompleted('t1');
    expect(q.get('t1')!.state, TransferState.completed);
    await q.close();
  });

  test('InboxWriter write finalize with sha256', () async {
    final inbox = Directory('${tmp.path}/inbox');
    final writer = InboxWriter(inboxDir: inbox);
    const id = 'xfer1';
    final data = List<int>.generate(200, (i) => i);
    final hash = Sha256Stream.hashBytes(data);
    await writer.writeChunk(
      transferId: id,
      relativePath: 'payload',
      offset: 0,
      bytes: data,
    );
    final dest = await writer.finalizeToInbox(
      transferId: id,
      desiredName: 'out.bin',
      expectedSha256: hash,
    );
    expect(await dest.exists(), isTrue);
    expect(await dest.length(), 200);
  });

  test('DiskSpace.hasRoomFor respects margin', () {
    const report = DiskSpaceReport(
      path: '/',
      freeBytes: 100 * 1024 * 1024,
      totalBytes: 1000 * 1024 * 1024,
    );
    expect(report.hasRoomFor(10 * 1024 * 1024), isTrue);
    expect(report.hasRoomFor(90 * 1024 * 1024), isFalse);
  });

  test('DiskSpaceReport unknown fails closed', () {
    final report = DiskSpaceReport.unknown('/inbox');
    expect(report.probeOk, isFalse);
    expect(report.hasRoomFor(1), isFalse);
  });

  test('InboxWriter rejects concurrent openWrite', () async {
    final inbox = Directory('${tmp.path}/concurrent');
    final writer = InboxWriter(inboxDir: inbox);
    const id = 'c1';
    final s1 = await writer.openWrite(
      transferId: id,
      relativePath: 'payload',
      offset: 0,
    );
    expect(
      () => writer.openWrite(
        transferId: id,
        relativePath: 'payload',
        offset: 0,
      ),
      throwsA(isA<BlobWriteConflictException>()),
    );
    await s1.close();
    final s2 = await writer.openWrite(
      transferId: id,
      relativePath: 'payload',
      offset: 0,
    );
    await s2.close();
  });

  test('uniqueFile adds suffix', () async {
    final dir = Directory('${tmp.path}/u')..createSync();
    await File('${dir.path}/a.txt').writeAsString('1');
    final f = await PathSanitize.uniqueFile(dir, 'a.txt');
    expect(f.path.contains('a (1).txt'), isTrue);
  });

  test('LanAddress prefers 192.168 over VPN/virtual', () {
    expect(LanAddress.scoreAddress('192.168.88.10', 'Ethernet'), greaterThan(200));
    expect(
      LanAddress.scoreAddress('192.168.88.10', 'Ethernet'),
      greaterThan(LanAddress.scoreAddress('10.0.0.5', 'Ethernet')),
    );
    expect(
      LanAddress.scoreAddress('10.0.0.5', 'Ethernet'),
      greaterThan(LanAddress.scoreAddress('172.16.1.2', 'Ethernet')),
    );
    expect(LanAddress.scoreAddress('169.254.1.1', 'Ethernet'), 0);
    expect(
      LanAddress.scoreAddress('192.168.1.2', 'Ethernet'),
      greaterThan(LanAddress.scoreAddress('192.168.1.2', 'vEthernet (WSL)')),
    );
    expect(
      LanAddress.scoreAddress('100.64.1.2', 'Tailscale'),
      lessThan(LanAddress.scoreAddress('10.1.1.1', 'Ethernet')),
    );
    expect(LanAddress.isPrivateRfc1918('192.168.0.1'), isTrue);
    expect(LanAddress.isPrivateRfc1918('8.8.8.8'), isFalse);
  });

  test('LanAddress.subnetBroadcast /24', () {
    expect(LanAddress.subnetBroadcast('192.168.88.10'), '192.168.88.255');
    expect(LanAddress.subnetBroadcast('10.1.2.3'), '10.1.2.255');
    expect(LanAddress.subnetBroadcast('172.16.5.9', prefixLength: 16), '172.16.255.255');
  });

  test('DeviceIdentity.updateDisplayName persists', () async {
    final data = Directory('${tmp.path}/id');
    final id = await DeviceIdentity.loadOrCreate(
      dataDir: data,
      displayName: 'OldName',
    );
    await id.updateDisplayName('NewLaptop', dataDir: data);
    expect(id.displayName, 'NewLaptop');
    final reloaded = await DeviceIdentity.loadOrCreate(
      dataDir: data,
      displayName: 'ignored',
    );
    expect(reloaded.displayName, 'NewLaptop');
  });

  test('AppConfig persists preferred_lan_host', () async {
    final file = File('${tmp.path}/config.json');
    final cfg = AppConfig(
      displayName: 'Test',
      inboxDir: '${tmp.path}/inbox',
      dataDir: '${tmp.path}/data',
      preferredLanHost: '192.168.1.50',
    );
    await cfg.save(file);
    final loaded = await AppConfig.load(file);
    expect(loaded.preferredLanHost, '192.168.1.50');
  });

  test('TransferJob.isTerminal for completed', () {
    final job = TransferJob(
      id: '1',
      peerId: const PeerId('p'),
      direction: TransferDirection.send,
      kind: TransferKind.file,
      name: 'a.txt',
      state: TransferState.completed,
      totalBytes: 10,
      transferredBytes: 10,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    expect(job.isTerminal, isTrue);
    expect(job.progressPercent, 100);
  });

  test('Outbox reloads transferring as pending', () async {
    final q1 = await OutboxQueue.open(tmp);
    await q1.enqueue(
      id: 'reload1',
      peerId: const PeerId('p'),
      direction: TransferDirection.send,
      kind: TransferKind.file,
      name: 'a.txt',
      totalBytes: 10,
      localPath: '/tmp/a.txt',
    );
    await q1.update('reload1', state: TransferState.transferring);
    await q1.close();

    final q2 = await OutboxQueue.open(tmp);
    expect(q2.get('reload1')!.state, TransferState.pending);
    await q2.close();
  });

  test('Outbox skips corrupt JSON', () async {
    final outboxDir = Directory('${tmp.path}/outbox')..createSync(recursive: true);
    await File('${outboxDir.path}/bad.json').writeAsString('{not json');
    final q = await OutboxQueue.open(tmp);
    expect(q.list(), isEmpty);
    await q.close();
  });

  test('InboxWriter resume append and sha mismatch', () async {
    final inbox = Directory('${tmp.path}/inbox2');
    final writer = InboxWriter(inboxDir: inbox);
    const id = 'resume1';
    final part1 = List<int>.generate(50, (i) => i);
    final part2 = List<int>.generate(50, (i) => i + 50);
    final full = [...part1, ...part2];
    final hash = Sha256Stream.hashBytes(full);

    await writer.writeChunk(
      transferId: id,
      relativePath: 'payload',
      offset: 0,
      bytes: part1,
    );
    expect(await writer.receivedBytes(id), 50);

    await writer.writeChunk(
      transferId: id,
      relativePath: 'payload',
      offset: 50,
      bytes: part2,
    );
    expect(await writer.receivedBytes(id), 100);

    await expectLater(
      writer.finalizeToInbox(
        transferId: id,
        desiredName: 'bad.bin',
        expectedSha256: '0' * 64,
      ),
      throwsA(isA<Sha256MismatchException>()),
    );

    await writer.writeChunk(
      transferId: 'resume2',
      relativePath: 'payload',
      offset: 0,
      bytes: full,
    );
    final dest = await writer.finalizeToInbox(
      transferId: 'resume2',
      desiredName: 'ok.bin',
      expectedSha256: hash,
    );
    expect(await dest.exists(), isTrue);
    expect(await dest.length(), 100);
  });

  test('TokenStore persists across open', () async {
    final data = Directory('${tmp.path}/tok');
    final s1 = await TokenStore.open(data);
    await s1.put('peer-a', 'secret-token');
    final s2 = await TokenStore.open(data);
    expect(s2.get('peer-a'), 'secret-token');
    await s2.remove('peer-a');
    expect(s2.get('peer-a'), isNull);
  });

  test('Outbox cancel and retry', () async {
    final q = await OutboxQueue.open(tmp);
    await q.enqueue(
      id: 'c1',
      peerId: const PeerId('p'),
      direction: TransferDirection.send,
      kind: TransferKind.file,
      name: 'a.txt',
      totalBytes: 10,
    );
    await q.markCancelled('c1');
    expect(q.get('c1')!.state, TransferState.cancelled);
    await q.retry('c1');
    expect(q.get('c1')!.state, TransferState.pending);
    expect(q.get('c1')!.retryCount, 1);
    await q.close();
  });
}
