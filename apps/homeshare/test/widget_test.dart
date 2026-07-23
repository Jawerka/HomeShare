import 'package:flutter_test/flutter_test.dart';
import 'package:homeshare/services/cli_args.dart';

void main() {
  test('CliArgs parses send target and show', () {
    final parsed = CliArgs.parse([
      '--show',
      '--target',
      'peer-1',
      '--send',
      r'C:\a.txt',
      r'D:\b.bin',
    ]);
    expect(parsed.show, isTrue);
    expect(parsed.targetPeerId, 'peer-1');
    expect(parsed.sendPaths, [r'C:\a.txt', r'D:\b.bin']);
  });

  test('CliArgs.expandPathArg keeps plain path', () {
    expect(CliArgs.expandPathArg(r'C:\solo.txt'), [r'C:\solo.txt']);
  });

  test('CliArgs.expandPathArg splits quoted multi-path', () {
    final paths = CliArgs.expandPathArg(r'"C:\a.txt" "D:\b.txt"');
    expect(paths, [r'C:\a.txt', r'D:\b.txt']);
  });
}
