import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

class ShareableFile {
  final String path;
  final String filename;
  final String mimeType;

  const ShareableFile({
    required this.path,
    required this.filename,
    required this.mimeType,
  });
}

class _ServedFile {
  final ShareableFile source;
  final String token;
  _ServedFile(this.source, this.token);
}

class LocalShareSession {
  final String indexUrl;
  final String localIp;
  final int port;
  final List<ShareableFile> files;
  final HttpServer _server;

  LocalShareSession._({
    required this.indexUrl,
    required this.localIp,
    required this.port,
    required this.files,
    required HttpServer server,
  }) : _server = server;

  Future<void> stop() async {
    try {
      await _server.close(force: true);
    } catch (_) {}
  }
}

class LocalShareService {
  static const _uuid = Uuid();

  static Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      String? fallback;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          final name = iface.name.toLowerCase();
          if (name.contains('en') ||
              name.contains('wlan') ||
              name.contains('wifi') ||
              name.contains('bridge')) {
            return addr.address;
          }
          fallback ??= addr.address;
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  static String _shortToken() =>
      _uuid.v4().replaceAll('-', '').substring(0, 12);

  static Future<LocalShareSession> start({
    required String title,
    required List<ShareableFile> files,
  }) async {
    final ip = await _getLocalIp();
    if (ip == null) {
      throw const _LocalShareException(
        'Aucun réseau Wi-Fi détecté. Connectez-vous au même Wi-Fi que le locataire (ou activez votre partage de connexion).',
      );
    }

    final served = files.map((f) => _ServedFile(f, _shortToken())).toList();
    final indexToken = _shortToken();

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.listen((req) async {
      try {
        await _handle(req, title, served, indexToken);
      } catch (_) {
        try {
          req.response.statusCode = 500;
          await req.response.close();
        } catch (_) {}
      }
    });

    final indexUrl = 'http://$ip:${server.port}/$indexToken';
    return LocalShareSession._(
      indexUrl: indexUrl,
      localIp: ip,
      port: server.port,
      files: files,
      server: server,
    );
  }

  static Future<void> _handle(
    HttpRequest req,
    String title,
    List<_ServedFile> served,
    String indexToken,
  ) async {
    final segments = req.uri.pathSegments;
    if (segments.length == 1 && segments.first == indexToken) {
      await _serveIndex(req, title, served, indexToken);
      return;
    }
    if (segments.length == 3 &&
        segments[0] == indexToken &&
        segments[1] == 'f') {
      final token = segments[2];
      final forceDownload = req.uri.queryParameters['dl'] == '1';
      for (final s in served) {
        if (s.token == token) {
          await _serveFile(req, s.source, forceDownload: forceDownload);
          return;
        }
      }
    }
    req.response.statusCode = 404;
    req.response.headers.contentType = ContentType.text;
    req.response.write('Not found');
    await req.response.close();
  }

  static Future<void> _serveIndex(
    HttpRequest req,
    String title,
    List<_ServedFile> served,
    String indexToken,
  ) async {
    final buf = StringBuffer();
    buf.writeln('<!DOCTYPE html><html lang="fr"><head>');
    buf.writeln('<meta charset="utf-8">');
    buf.writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1">');
    buf.writeln('<title>${_esc(title)}</title>');
    buf.writeln('<style>');
    buf.writeln(
        'body{font-family:-apple-system,system-ui,sans-serif;margin:0;padding:24px;max-width:640px;margin:0 auto;background:#f3f4f6;color:#111}');
    buf.writeln('h1{font-size:20px;margin:0 0 4px}');
    buf.writeln('p.sub{color:#555;margin:0 0 20px;font-size:14px}');
    buf.writeln('ul{list-style:none;padding:0;margin:0}');
    buf.writeln(
        'li{background:#fff;border-radius:12px;margin-bottom:10px;box-shadow:0 1px 3px rgba(0,0,0,.06);padding:14px 16px}');
    buf.writeln('.fname{font-size:15px;font-weight:600;word-break:break-all;color:#111}');
    buf.writeln(
        '.ftype{font-size:12px;color:#666;margin-top:2px}');
    buf.writeln(
        '.actions{margin-top:10px;display:flex;gap:8px;flex-wrap:wrap}');
    buf.writeln(
        '.btn{display:inline-block;padding:9px 14px;border-radius:8px;font-size:14px;font-weight:600;text-decoration:none;text-align:center;flex:1;min-width:110px}');
    buf.writeln('.btn-open{background:#1e3a8a;color:#fff}');
    buf.writeln('.btn-dl{background:#fff;color:#1e3a8a;border:1px solid #1e3a8a}');
    buf.writeln('.btn:active{opacity:.7}');
    buf.writeln(
        '.foot{font-size:11px;color:#888;text-align:center;margin-top:24px}');
    buf.writeln('</style></head><body>');
    buf.writeln('<h1>📂 ${_esc(title)}</h1>');
    buf.writeln(
        '<p class="sub">Appuyez sur <b>Ouvrir</b> pour visualiser, ou <b>Télécharger</b> pour enregistrer.</p>');
    buf.writeln('<ul>');
    for (final s in served) {
      buf.writeln('<li>');
      buf.writeln('<div class="fname">${_esc(s.source.filename)}</div>');
      buf.writeln('<div class="ftype">${_esc(s.source.mimeType)}</div>');
      buf.writeln('<div class="actions">');
      buf.writeln(
          '<a class="btn btn-open" href="/$indexToken/f/${s.token}" target="_blank" rel="noopener">Ouvrir</a>');
      buf.writeln(
          '<a class="btn btn-dl" href="/$indexToken/f/${s.token}?dl=1" download="${_esc(s.source.filename)}">Télécharger</a>');
      buf.writeln('</div>');
      buf.writeln('</li>');
    }
    buf.writeln('</ul>');
    buf.writeln(
        '<p class="foot">ADDA Bailleur · partage Wi-Fi local · ${served.length} fichier(s)</p>');
    buf.writeln('</body></html>');

    req.response.statusCode = 200;
    req.response.headers.contentType =
        ContentType('text', 'html', charset: 'utf-8');
    req.response.headers.set('Cache-Control', 'no-store');
    req.response.write(buf.toString());
    await req.response.close();
  }

  static Future<void> _serveFile(
    HttpRequest req,
    ShareableFile f, {
    bool forceDownload = false,
  }) async {
    final file = File(f.path);
    if (!await file.exists()) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final stat = await file.stat();
    final parts = f.mimeType.split('/');
    final ct = parts.length == 2
        ? ContentType(parts[0], parts[1])
        : ContentType.binary;
    final disposition = forceDownload ? 'attachment' : 'inline';
    req.response.statusCode = 200;
    req.response.headers.contentType = ct;
    req.response.headers.contentLength = stat.size;
    req.response.headers.set(
      'Content-Disposition',
      '$disposition; filename="${_safeFilename(f.filename)}"',
    );
    req.response.headers.set('Cache-Control', 'no-store');
    await file.openRead().pipe(req.response);
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static String _safeFilename(String s) =>
      s.replaceAll(RegExp(r'[\r\n"\\]'), '_');
}

class _LocalShareException implements Exception {
  final String message;
  const _LocalShareException(this.message);

  @override
  String toString() => message;
}
