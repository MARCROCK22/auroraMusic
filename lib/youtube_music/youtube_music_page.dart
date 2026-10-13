import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'youtube_music_ad_blocker.dart';
import 'youtube_music_navigation.dart';
import 'youtube_music_platform.dart';

export 'youtube_music_platform.dart' show YouTubeMusicPlatform;

/// A visible, full-size official website, independent of Aurora's audio queue.
/// Keep this widget mounted while visible to retain its WebView and history.
/// Shell navigation must await [YouTubeMusicPageState.confirmExit] before removal.
class YouTubeMusicPage extends StatefulWidget {
  const YouTubeMusicPage({
    super.key,
    this.initialUri,
    this.onClosed,
    @visibleForTesting this.platform,
    @visibleForTesting this.openExternal,
  });

  final Uri? initialUri;
  final VoidCallback? onClosed;
  final YouTubeMusicPlatform? platform;
  final Future<bool> Function(Uri uri)? openExternal;

  @override
  State<YouTubeMusicPage> createState() => YouTubeMusicPageState();
}

class YouTubeMusicPageState extends State<YouTubeMusicPage> {
  late final YouTubeMusicPlatform _platform;
  Widget? _view;
  String? _initializationError;
  String? _commandError;
  Future<bool>? _exitConfirmation;
  bool _busy = false;
  bool _closing = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _platform = widget.platform ?? NativeYouTubeMusicPlatform();
    _platform.addListener(_changed);
    unawaited(_initialize());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant YouTubeMusicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_view != null && oldWidget.initialUri != widget.initialUri) {
      unawaited(
        _run(() => _platform.navigateTo(widget.initialUri ?? youtubeMusicHome)),
      );
    }
  }

  Future<void> _initialize() async {
    var initialUri = widget.initialUri ?? youtubeMusicHome;
    try {
      if (classifyYouTubeMusicNavigation(initialUri) !=
          YouTubeMusicNavigation.allow) {
        throw ArgumentError(
          'La dirección inicial debe ser una página oficial HTTPS de YouTube Music.',
        );
      }
      await _platform.initialize();
      if (!mounted) return;
      initialUri = widget.initialUri ?? youtubeMusicHome;
      final view = _platform.buildView(initialUri);
      setState(() {
        _initializationError = null;
        _view = view;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializationError = error is UnsupportedError
            ? error.message
            : error is StateError
            ? error.message
            : 'No se pudo abrir la vista de YouTube Music. Revisa la configuración del dispositivo y vuelve a intentar.';
      });
    }
  }

  Future<void> _run(Future<void> Function() command) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _commandError = null;
    });
    try {
      await command();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commandError =
            'No se pudo completar la acción. Inténtalo de nuevo o abre YouTube Music en tu navegador.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBrowser() => _run(() async {
    // Open the public home, never forward login tokens or export cookies.
    final opened =
        await (widget.openExternal?.call(youtubeMusicHome) ??
            launchUrl(youtubeMusicHome, mode: LaunchMode.externalApplication));
    if (!opened) throw StateError('Browser unavailable');
  });

  /// Returns permission to leave without changing website media state.
  /// Native playback state is unavailable on both targets, so ask conservatively.
  Future<bool> confirmExit() {
    if (!mounted) return Future.value(false);
    if (_view == null) return Future.value(true);
    return _exitConfirmation ??= _showExitConfirmation().whenComplete(() {
      _exitConfirmation = null;
    });
  }

  Future<bool> _showExitConfirmation() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('¿Salir de YouTube Music?'),
          content: const Text(
            'Al salir, la reproducción de YouTube Music puede detenerse. ¿Quieres continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Quedarme'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salir'),
            ),
          ],
        ),
      ) ??
      false;

  /// Android back first traverses official website history, then confirms exit.
  Future<void> handleBack() async {
    if (_busy || _closing) return;
    if (_platform.ready && _platform.canGoBack) {
      await _run(_platform.goBack);
      return;
    }
    await _close();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      if (!await confirmExit() || !mounted) return;
      if (widget.onClosed != null) {
        widget.onClosed!();
      } else {
        setState(() => _allowPop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) await Navigator.of(context).maybePop();
      }
    } finally {
      _closing = false;
    }
  }

  @override
  void dispose() {
    _platform.removeListener(_changed);
    _platform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _platform.ready && !_busy;
    final message = _commandError ?? _platform.error ?? _platform.notice;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(handleBack());
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 16,
                  end: 4,
                  top: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'YouTube Music',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Abrir en navegador',
                      onPressed: _busy ? null : _openBrowser,
                      icon: const Icon(Icons.open_in_new),
                    ),
                    IconButton(
                      tooltip: 'Cerrar YouTube Music',
                      onPressed: _closing ? null : _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Atrás',
                    onPressed: enabled && _platform.canGoBack
                        ? () => _run(_platform.goBack)
                        : null,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  IconButton(
                    tooltip: 'Adelante',
                    onPressed: enabled && _platform.canGoForward
                        ? () => _run(_platform.goForward)
                        : null,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  IconButton(
                    tooltip: 'Recargar',
                    onPressed: enabled ? () => _run(_platform.reload) : null,
                    icon: const Icon(Icons.refresh),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 16),
                      child: Text(
                        'music.youtube.com',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 3,
                child: _platform.loading && _initializationError == null
                    ? LinearProgressIndicator(
                        value: _platform.progress > 0
                            ? _platform.progress
                            : null,
                      )
                    : const SizedBox.expand(),
              ),
              if (_platform.adBlocker case final blocker?)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: MergeSemantics(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Filtro de anuncios'),
                              Text(
                                !blocker.enabled
                                    ? 'Desactivado'
                                    : switch (blocker.status) {
                                        YouTubeMusicAdBlockStatus.loading =>
                                          'Preparando…',
                                        YouTubeMusicAdBlockStatus.ready =>
                                          'Activo',
                                        YouTubeMusicAdBlockStatus.failed =>
                                          'No disponible',
                                      },
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message:
                              'Filtra recursos publicitarios. No garantiza eliminar anuncios de video. Desactívalo si la página falla.',
                          child: Switch.adaptive(
                            value: blocker.enabled,
                            onChanged: (value) {
                              blocker.setEnabled(value);
                              if (value &&
                                  blocker.status ==
                                      YouTubeMusicAdBlockStatus.failed) {
                                unawaited(blocker.initialize());
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (message != null && _view != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .35,
                  ),
                  child: SingleChildScrollView(
                    child: ColoredBox(
                      color: colors.surfaceContainerHigh,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(message, semanticsLabel: message),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (_platform.error != null ||
                                    _commandError != null)
                                  TextButton(
                                    onPressed: enabled
                                        ? () => _run(_platform.reload)
                                        : null,
                                    child: const Text('Reintentar'),
                                  ),
                                TextButton(
                                  onPressed: _busy ? null : _openBrowser,
                                  child: const Text('Abrir en navegador'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child:
                    _view ??
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: _initializationError == null
                            ? Semantics(
                                label: 'Abriendo YouTube Music',
                                child: const CircularProgressIndicator(),
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.public_off, size: 40),
                                  const SizedBox(height: 16),
                                  Text(
                                    _initializationError!,
                                    textAlign: TextAlign.center,
                                  ),
                                  if (_commandError != null)
                                    Text(_commandError!),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _run(_initialize),
                                        child: const Text('Reintentar'),
                                      ),
                                      TextButton(
                                        onPressed: _busy ? null : _openBrowser,
                                        child: const Text('Abrir en navegador'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
