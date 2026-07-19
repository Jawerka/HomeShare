import 'dart:math' as math;

/// Minimal QR-looking SVG for pairing payloads.
///
/// Primary pairing channel is the large PIN digits; the matrix is a
/// deterministic visual encoding of the URI for the Web UI.
class QrSvg {
  static String encode(String data, {int size = 240}) {
    final modules = _QrEncoder.encode(data);
    final n = modules.length;
    const quiet = 4;
    final dim = n + quiet * 2;
    final cell = size / dim;
    final sb = StringBuffer();
    sb.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" '
      'viewBox="0 0 $size $size" shape-rendering="crispEdges">',
    );
    sb.writeln('<rect width="100%" height="100%" fill="#fff"/>');
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (modules[y][x]) {
          final px = (x + quiet) * cell;
          final py = (y + quiet) * cell;
          sb.writeln(
            '<rect x="${px.toStringAsFixed(2)}" y="${py.toStringAsFixed(2)}" '
            'width="${cell.toStringAsFixed(2)}" height="${cell.toStringAsFixed(2)}" fill="#000"/>',
          );
        }
      }
    }
    sb.writeln('</svg>');
    return sb.toString();
  }
}

class _QrEncoder {
  static List<List<bool>> encode(String text) {
    final bytes = text.codeUnits;
    final version = bytes.length <= 32 ? 3 : (bytes.length <= 84 ? 5 : 10);
    return _build(version, bytes);
  }

  static List<List<bool>> _build(int version, List<int> data) {
    final size = version * 4 + 17;
    final modules = List.generate(size, (_) => List.filled(size, false));
    final reserved = List.generate(size, (_) => List.filled(size, false));

    void set(int x, int y, bool v, {bool reserve = true}) {
      if (x < 0 || y < 0 || x >= size || y >= size) return;
      modules[y][x] = v;
      if (reserve) reserved[y][x] = true;
    }

    void finder(int ox, int oy) {
      for (var y = -1; y <= 7; y++) {
        for (var x = -1; x <= 7; x++) {
          final xx = ox + x;
          final yy = oy + y;
          final inPat = x >= 0 && x <= 6 && y >= 0 && y <= 6;
          final black = inPat &&
              (x == 0 ||
                  x == 6 ||
                  y == 0 ||
                  y == 6 ||
                  (x >= 2 && x <= 4 && y >= 2 && y <= 4));
          if (xx >= 0 && yy >= 0 && xx < size && yy < size) {
            set(xx, yy, black);
          }
        }
      }
    }

    finder(0, 0);
    finder(size - 7, 0);
    finder(0, size - 7);

    for (var i = 8; i < size - 8; i++) {
      set(i, 6, i.isEven);
      set(6, i, i.isEven);
    }
    set(8, size - 8, true);

    final bits = <bool>[];
    for (final b in data) {
      for (var i = 7; i >= 0; i--) {
        bits.add(((b >> i) & 1) == 1);
      }
    }
    while (bits.length < size * size) {
      bits.add((bits.length % (3 + version)).isEven);
    }

    var bit = 0;
    var direction = -1;
    var col = size - 1;
    while (col > 0) {
      if (col == 6) col--;
      for (var i = 0; i < size; i++) {
        final y = direction < 0 ? size - 1 - i : i;
        for (final c in [col, col - 1]) {
          if (!reserved[y][c]) {
            final v = bits[bit % bits.length];
            modules[y][c] = ((c + y + version).isEven) ? !v : v;
            bit++;
          }
        }
      }
      direction = -direction;
      col -= 2;
    }

    assert(size > math.log(version + 1));
    return modules;
  }
}
