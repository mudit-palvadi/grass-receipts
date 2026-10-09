/// Owns the on-device Gemma engine: initialisation, model download, readiness.
///
/// Lifted from the Heads Up project (lib/services/gemma_runtime.dart), which
/// already proved this path on a real Android phone. Two details from that file
/// are carried over verbatim because they are the ones that cost an afternoon
/// to learn:
///
///  1. The file **must** be named explicitly. Left to itself the manifest
///     resolver guesses a conventional filename, 404s, and reports "Model not
///     found" — which reads like a bad repo id rather than a missing file
///     argument.
///  2. The download is hundreds of MB, so progress is throttled before it
///     reaches the UI. The callback fires far more often than the screen can
///     repaint, and each emit fans out to a broadcast stream.
///
/// Two things deliberately differ from Heads Up:
///
///  * Any of several open-weight models can be loaded, not just one. The
///    receipt prompt is model-agnostic, so swapping the file swaps the jokes.
///    That swap is the whole point of an open-source AI submission, and it is
///    worth being able to demonstrate it rather than claim it.
///  * The Hugging Face token lives in memory for the length of one download
///    and is never written to disk here.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

/// A downloadable open-weight model, as a concrete file in a concrete repo.
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.label,
    required this.repo,
    required this.file,
    required this.modelType,
    required this.fileType,
    required this.sizeMb,
    required this.requiresToken,
    required this.note,
  });

  final String id;
  final String label;

  /// Hugging Face repository id.
  final String repo;

  /// Exact filename. See the library comment on why this must be spelled out.
  final String file;

  final ModelType modelType;
  final ModelFileType fileType;

  /// Approximate download size, for the setup screen.
  final int sizeMb;

  /// True when the repo is gated behind a licence a token must be accepted for.
  final bool requiresToken;

  /// One line of honest context, shown on the model picker.
  final String note;

  static const ModelSpec qwen3 = ModelSpec(
    id: 'qwen3_0_6b',
    label: 'Qwen3 0.6B (INT4)',
    repo: 'litert-community/Qwen3-0.6B',
    file: 'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
    modelType: ModelType.qwen3,
    fileType: ModelFileType.litertlm,
    sizeMb: 329,
    requiresToken: false,
    note: 'No account, no token, no licence click. Clone and run.',
  );

  static const ModelSpec smolLM2 = ModelSpec(
    id: 'smollm2_360m',
    label: 'SmolLM2 360M Instruct',
    repo: 'litert-community/SmolLM2-360M-Instruct',
    file: 'SmolLM2_360M_instruct.litertlm',
    modelType: ModelType.general,
    fileType: ModelFileType.litertlm,
    sizeMb: 356,
    requiresToken: false,
    note: 'Ungated and the fastest on a weak phone, at the cost of wit.',
  );

  static const ModelSpec gemma3 = ModelSpec(
    id: 'gemma3_1b',
    label: 'Gemma 3 1B-IT (INT4)',
    repo: 'litert-community/Gemma3-1B-IT',
    file: 'gemma3-1b-it-int4.litertlm',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.litertlm,
    sizeMb: 529,
    requiresToken: true,
    note: 'The prize-category model. Needs a Hugging Face token with the '
        'Gemma licence accepted.',
  );

  static const List<ModelSpec> all = [qwen3, smolLM2, gemma3];

  /// The default, because it needs nothing from the person running it.
  static const ModelSpec defaultSpec = qwen3;

  static ModelSpec byId(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => defaultSpec);
}

/// State of the local model, shown on the setup screen.
enum ModelStatus {
  notDownloaded,
  downloading,
  ready,
  failed,
}

/// What the model is doing right now.
class ModelState {
  const ModelState({
    required this.status,
    this.progress = 0,
    this.message,
  });

  final ModelStatus status;

  /// 0.0 to 1.0 while downloading.
  final double progress;

  /// Human-readable detail, e.g. a download failure.
  final String? message;

  bool get isBusy => status == ModelStatus.downloading;
}

class GemmaRuntime {
  GemmaRuntime({this.spec = ModelSpec.defaultSpec});

  /// Which model to install and load.
  ModelSpec spec;

  bool _initialised = false;

  /// The Hugging Face token, held only while the model is being downloaded.
  String? _token;

  ModelState _state = const ModelState(status: ModelStatus.notDownloaded);
  ModelState get state => _state;

  final StreamController<ModelState> _changes =
      StreamController<ModelState>.broadcast();

  /// Emits on every state transition so the UI can show progress.
  Stream<ModelState> get changes => _changes.stream;

  /// Starts the engine. Safe to call repeatedly.
  Future<void> initialise() async {
    if (_initialised) return;

    try {
      await FlutterGemma.initialize(
        huggingFaceToken: (_token?.isEmpty ?? true) ? null : _token,
        inferenceEngines: const [LiteRtLmEngine()],
      );
      _initialised = true;

      // An already-installed model means the download never has to happen
      // again, which is the common path after the first run.
      try {
        await FlutterGemma.getActiveModel();
        _emit(const ModelState(status: ModelStatus.ready, progress: 1));
      } catch (_) {
        _emit(const ModelState(status: ModelStatus.notDownloaded));
      }
    } catch (e) {
      debugPrint('GemmaRuntime: engine init failed: $e');
      _emit(const ModelState(
        status: ModelStatus.failed,
        message: 'Could not start the Gemma engine.',
      ));
    }
  }

  /// Hands the runtime a Hugging Face token for the duration of one download.
  ///
  /// Only the gated repos need it: the Qwen3 and SmolLM2 specs above download
  /// with no credentials at all, so this exists purely so the Gemma prize
  /// category is reachable from the same app.
  void setToken(String? token) {
    _token = token?.trim();
    // The engine must be re-created to pick the token up.
    _initialised = false;
  }

  /// Changes which model is loaded. Resets readiness, because the previously
  /// installed file belongs to the previous repo.
  void setSpec(ModelSpec next) {
    if (next.id == spec.id) return;
    spec = next;
    _initialised = false;
    _emit(const ModelState(status: ModelStatus.notDownloaded));
  }

  /// Downloads the model if it is not already present.
  ///
  /// Idempotent — `install()` returns immediately when the file exists, so this
  /// is safe to call on every app start to refresh [state].
  Future<bool> ensureModelInstalled() async {
    if (!_initialised) await initialise();
    if (!_initialised) return false;

    if (spec.requiresToken && (_token?.isEmpty ?? true)) {
      // Built as a local because ${spec.label} interpolates an instance field,
      // which cannot appear inside a const constructor call.
      final message =
          '${spec.label} needs a Hugging Face token. Paste one on the setup '
          'screen, or pick a model that needs no account.';
      _emit(ModelState(status: ModelStatus.failed, message: message));
      return false;
    }

    _emit(const ModelState(status: ModelStatus.downloading, progress: 0));

    try {
      final installation = await FlutterGemma
          .installModel(modelType: spec.modelType, fileType: spec.fileType)
          .fromHuggingFace(spec.repo, file: spec.file)
          .withProgress((progress) => _emit(ModelState(
                status: ModelStatus.downloading,
                progress: progress / 100,
              )))
          .install();

      _emit(const ModelState(status: ModelStatus.ready, progress: 1));
      debugPrint('GemmaRuntime: model installed: ${installation.spec}');
      return true;
    } catch (e) {
      _emit(ModelState(status: ModelStatus.failed, message: explain(e)));
      return false;
    }
  }

  /// Turns a download failure into something worth showing a non-technical
  /// person. A 401 is the one that matters most and the least obvious: it means
  /// the licence has not been accepted, not that the network is down.
  String explain(Object error) {
    final text = error.toString();
    if (text.contains('401') || text.contains('Unauthorized')) {
      return 'Hugging Face refused the download (401). ${spec.label} sits in a '
          'gated repo: check the licence is accepted and the token has read '
          'access, or pick a model that needs no account.';
    }
    if (text.contains('403')) {
      return 'That token is not allowed to read ${spec.repo} (403).';
    }
    if (text.contains('404')) {
      return 'Could not find ${spec.file} in ${spec.repo} (404).';
    }
    if (text.contains('SocketException') || text.contains('Failed host lookup')) {
      return 'No internet connection. The model needs a one-time download.';
    }
    return 'Model download failed: $error';
  }

  void _emit(ModelState next) {
    _state = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  void dispose() {
    unawaited(_changes.close());
  }
}
