// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';
import 'package:process/process.dart';

import '../base/bot_detector.dart';
import '../base/common.dart';
import '../base/context.dart';
import '../base/file_system.dart';
import '../base/io.dart' as io;
import '../base/io.dart';
import '../base/logger.dart';
import '../base/platform.dart';
import '../base/process.dart';
import '../cache.dart';
import '../convert.dart';
import '../dart/package_map.dart';
import '../project.dart';
import '../reporting/reporting.dart';

/// The [Pub] instance.
Pub get pub => context.get<Pub>()!;

/// The console environment key used by the pub tool.
const String _kPubEnvironmentKey = 'PUB_ENVIRONMENT';

/// The console environment key used by the pub tool to find the cache directory.
const String _kPubCacheEnvironmentKey = 'PUB_CACHE';

typedef MessageFilter = String? Function(String message);

bool _tryDeleteDirectory(Directory directory, Logger logger) {
  try {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  } on FileSystemException {
    logger.printWarning('Failed to delete directory at: ${directory.path}');
    return false;
  }
  return true;
}

/// Represents Flutter-specific data that is added to the `PUB_ENVIRONMENT`
/// environment variable and allows understanding the type of requests made to
/// the package site on Flutter's behalf.
// DO NOT update without contacting kevmoo.
// We have server-side tooling that assumes the values are consistent.
class PubContext {
  PubContext._(this._values) {
    for (final String item in _values) {
      if (!_validContext.hasMatch(item)) {
        throw ArgumentError.value(
          _values, 'value', 'Must match RegExp ${_validContext.pattern}');
      }
    }
  }

  static PubContext getVerifyContext(String commandName) =>
      PubContext._(<String>['verify', commandName.replaceAll('-', '_')]);

  static final PubContext create = PubContext._(<String>['create']);
  static final PubContext createPackage = PubContext._(<String>['create_pkg']);
  static final PubContext createPlugin = PubContext._(<String>['create_plugin']);
  static final PubContext interactive = PubContext._(<String>['interactive']);
  static final PubContext pubGet = PubContext._(<String>['get']);
  static final PubContext pubUpgrade = PubContext._(<String>['upgrade']);
  static final PubContext pubAdd = PubContext._(<String>['add']);
  static final PubContext pubRemove = PubContext._(<String>['remove']);
  static final PubContext pubForward = PubContext._(<String>['forward']);
  static final PubContext pubPassThrough = PubContext._(<String>['passthrough']);
  static final PubContext runTest = PubContext._(<String>['run_test']);
  static final PubContext flutterTests = PubContext._(<String>['flutter_tests']);
  static final PubContext updatePackages = PubContext._(<String>['update_packages']);

  final List<String> _values;

  static final RegExp _validContext = RegExp('[a-z][a-z_]*[a-z]');

  @override
  String toString() => 'PubContext: ${_values.join(':')}';

  String toAnalyticsString()  {
    return _values.map((String s) => s.replaceAll('_', '-')).toList().join('-');
  }
}

/// Describes the amount of output that should get printed from a `pub` command.
/// [PubOutputMode.all] indicates that the complete output is printed. This is
/// typically the default.
/// [PubOutputMode.none] indicates that no output should be printed.
/// [PubOutputMode.summaryOnly] indicates that only summary information should be printed.
enum PubOutputMode {
  none,
  all,
  summaryOnly,
}

/// A handle for interacting with the pub tool.
abstract class Pub {
  /// Create a default [Pub] instance.
  factory Pub({
    required FileSystem fileSystem,
    required Logger logger,
    required ProcessManager processManager,
    required Platform platform,
    required BotDetector botDetector,
    required Usage usage,
  }) = _DefaultPub;

  /// Create a [Pub] instance with a mocked [stdio].
  @visibleForTesting
  factory Pub.test({
    required FileSystem fileSystem,
    required Logger logger,
    required ProcessManager processManager,
    required Platform platform,
    required BotDetector botDetector,
    required Usage usage,
    required Stdio stdio,
  }) = _DefaultPub.test;

  /// Runs `pub get` for [project].
  ///
  /// [context] provides extra information to package server requests to
  /// understand usage.
  ///
  /// If [shouldSkipThirdPartyGenerator] is true, the overall pub get will be
  /// skipped if the package config file has a "generator" other than "pub".
  /// Defaults to true.
  ///
  /// [outputMode] determines how verbose the output from `pub get` will be.
  /// If [PubOutputMode.all] is used, `pub get` will print its typical output
  /// which includes information about all changed dependencies. If
  /// [PubOutputMode.summaryOnly] is used, only summary information will be printed.
  /// This is useful for cases where the user is typically not interested in
  /// what dependencies were changed, such as when running `flutter create`.
  ///
  /// Will also resolve dependencies in the example folder if present.
  Future<void> get({
    required PubContext context,
    required FlutterProject project,
    bool upgrade = false,
    bool offline = false,
    String? flutterRootOverride,
    bool checkUpToDate = false,
    bool shouldSkipThirdPartyGenerator = true,
    PubOutputMode outputMode = PubOutputMode.all,
  });

  /// Runs pub in 'batch' mode.
  ///
  /// forwarding complete lines written by pub to its stdout/stderr streams to
  /// the corresponding stream of this process, optionally applying filtering.
  /// The pub process will not receive anything on its stdin stream.
  ///
  /// The `--trace` argument is passed to `pub` when `showTraceForErrors`
  /// `isRunningOnBot` is true.
  ///
  /// [context] provides extra information to package server requests to
  /// understand usage.
  Future<void> batch(
    List<String> arguments, {
    required PubContext context,
    String? directory,
    MessageFilter? filter,
    String failureMessage = 'pub failed',
  });

  /// Runs pub in 'interactive' mode.
  ///
  /// This will run the pub process with StdioInherited (unless [_stdio] is set
  /// for testing).
  ///
  /// The pub process will be run in current working directory, so `--directory`
  /// should be passed appropriately in [arguments]. This ensures output from
  /// pub will refer to relative paths correctly.
  ///
  /// [touchesPackageConfig] should be true if this is a command expected to
  /// create a new `.dart_tool/package_config.json` file.
  Future<void> interactively(
    List<String> arguments, {
    FlutterProject? project,
    required PubContext context,
    required String command,
    bool touchesPackageConfig = false,
    bool generateSyntheticPackage = false,
    PubOutputMode outputMode = PubOutputMode.all
  });
}

class _DefaultPub implements Pub {
  _DefaultPub({
    required FileSystem fileSystem,
    required Logger logger,
    required ProcessManager processManager,
    required Platform platform,
    required BotDetector botDetector,
    required Usage usage,
  }) : _fileSystem = fileSystem,
       _logger = logger,
       _platform = platform,
       _botDetector = botDetector,
       _usage = usage,
       _processUtils = ProcessUtils(
         logger: logger,
         processManager: processManager,
       ),
       _processManager = processManager,
       _stdio = null;

  @visibleForTesting
  _DefaultPub.test({
    required FileSystem fileSystem,
    required Logger logger,
    required ProcessManager processManager,
    required Platform platform,
    required BotDetector botDetector,
    required Usage usage,
    required Stdio stdio,
  }) : _fileSystem = fileSystem,
       _logger = logger,
       _platform = platform,
       _botDetector = botDetector,
       _usage = usage,
       _processUtils = ProcessUtils(
         logger: logger,
         processManager: processManager,
       ),
       _processManager = processManager,
       _stdio = stdio;

  final FileSystem _fileSystem;
  final Logger _logger;
  final ProcessUtils _processUtils;
  final Platform _platform;
  final BotDetector _botDetector;
  final Usage _usage;
  final ProcessManager _processManager;
  final Stdio? _stdio;

  @override
  Future<void> get({
    required PubContext context,
    required FlutterProject project,
    bool upgrade = false,
    bool offline = false,
    bool generateSyntheticPackage = false,
    bool generateSyntheticPackageForExample = false,
    String? flutterRootOverride,
    bool checkUpToDate = false,
    bool shouldSkipThirdPartyGenerator = true,
    PubOutputMode outputMode = PubOutputMode.all,
  }) async {
    final String directory = project.directory.path;
    final File packageConfigFile = project.packageConfigFile;
    final File lastVersion = _fileSystem.file(
      _fileSystem.path.join(directory, '.dart_tool', 'version'));
    final File currentVersion = _fileSystem.file(
      _fileSystem.path.join(Cache.flutterRoot!, 'version'));
    final File pubspecYaml = project.pubspecFile;
    final File pubLockFile = _fileSystem.file(
      _fileSystem.path.join(directory, 'pubspec.lock')
    );

    if (shouldSkipThirdPartyGenerator && project.packageConfigFile.existsSync()) {
      Map<String, Object?> packageConfigMap;
      try {
        packageConfigMap = jsonDecode(
          project.packageConfigFile.readAsStringSync(),
        ) as Map<String, Object?>;
      } on FormatException {
        packageConfigMap = <String, Object?>{};
      }

      final bool isPackageConfigGeneratedByThirdParty =
          packageConfigMap.containsKey('generator') &&
          packageConfigMap['generator'] != 'pub';

      if (isPackageConfigGeneratedByThirdParty) {
        _logger.printTrace('Skipping pub get: generated by third-party.');
        return;
      }
    }

    // If the pubspec.yaml is older than the package config file and the last
    // flutter version used is the same as the current version skip pub get.
    // This will incorrectly skip pub on the master branch if dependencies
    // are being added/removed from the flutter framework packages, but this
    // can be worked around by manually running pub.
    if (checkUpToDate &&
        packageConfigFile.existsSync() &&
        pubLockFile.existsSync() &&
        pubspecYaml.lastModifiedSync().isBefore(pubLockFile.lastModifiedSync()) &&
        pubspecYaml.lastModifiedSync().isBefore(packageConfigFile.lastModifiedSync()) &&
        lastVersion.existsSync() &&
        lastVersion.readAsStringSync() == currentVersion.readAsStringSync()) {
      _logger.printTrace('Skipping pub get: version match.');
      return;
    }

    final String command = upgrade ? 'upgrade' : 'get';
    final bool verbose = _logger.isVerbose;
    final List<String> args = <String>[
      if (_logger.supportsColor)
        '--color',
      if (verbose)
        '--verbose',
      '--directory',
      _fileSystem.path.relative(directory),
      ...<String>[
        command,
      ],
      if (offline)
        '--offline',
      '--example',
    ];
    await _runWithStdioInherited(
      args,
      command: command,
      context: context,
      directory: directory,
      failureMessage: 'pub $command failed',
      flutterRootOverride: flutterRootOverride,
      outputMode: outputMode,
    );
    await _updateVersionAndPackageConfig(project);
  }

  /// Runs pub with [arguments] and [ProcessStartMode.inheritStdio] mode.
  ///
  /// Uses [ProcessStartMode.normal] and [Pub._stdio] if [Pub.test] constructor
  /// was used.
  ///
  /// Prints the stdout and stderr of the whole run, unless silenced using
  /// [printProgress].
  ///
  /// Sends an analytics event.
  Future<void> _runWithStdioInherited(
    List<String> arguments, {
    required String command,
    required PubOutputMode outputMode,
    required PubContext context,
    required String directory,
    String failureMessage = 'pub failed',
    String? flutterRootOverride,
  }) async {
    int exitCode;

    final List<String> pubCommand = <String>[..._pubCommand, ...arguments];
    final Map<String, String> pubEnvironment = await _createPubEnvironment(context: context, flutterRootOverride: flutterRootOverride, summaryOnly: outputMode == PubOutputMode.summaryOnly);

    try {
      if (outputMode != PubOutputMode.none) {
        final io.Stdio? stdio = _stdio;
        if (stdio == null) {
          // Let pub inherit stdio and output directly to the tool's stdout and
          // stderr handles.
          final io.Process process = await _processUtils.start(
            pubCommand,
            workingDirectory: _fileSystem.path.current,
            environment: pubEnvironment,
            mode: ProcessStartMode.inheritStdio,
          );

          exitCode = await process.exitCode;
        } else {
          // Omit [mode] parameter to send output to [process.stdout] and
          // [process.stderr].
          final io.Process process = await _processUtils.start(
            pubCommand,
            workingDirectory: _fileSystem.path.current,
            environment: pubEnvironment,
          );

          // Direct pub output to [Pub._stdio] for tests.
          final StreamSubscription<List<int>> stdoutSubscription =
              process.stdout.listen(stdio.stdout.add);
          final StreamSubscription<List<int>> stderrSubscription =
              process.stderr.listen(stdio.stderr.add);

          await Future.wait<void>(<Future<void>>[
            stdoutSubscription.asFuture<void>(),
            stderrSubscription.asFuture<void>(),
          ]);

          unawaited(stdoutSubscription.cancel());
          unawaited(stderrSubscription.cancel());

          exitCode = await process.exitCode;
        }
      } else {
        // Do not try to use [ProcessUtils.start] here, because it requires you
        // to read all data out of the stdout and stderr streams. If you don't
        // read the streams, it may appear to work fine on your platform but
        // will block the tool's process on Windows.
        // See https://api.dart.dev/stable/dart-io/Process/start.html
        //
        // [ProcessUtils.run] will send the output to [result.stdout] and
        // [result.stderr], which we will ignore.
        final RunResult result = await _processUtils.run(
          pubCommand,
          workingDirectory: _fileSystem.path.current,
          environment: pubEnvironment,
        );

        exitCode = result.exitCode;
      }
    // The exception is rethrown, so don't catch only Exceptions.
    } catch (exception) { // ignore: avoid_catches_without_on_clauses
      if (exception is io.ProcessException) {
        final StringBuffer buffer = StringBuffer('${exception.message}\n');
        final String directoryExistsMessage = _fileSystem.directory(directory).existsSync()
            ? 'exists'
            : 'does not exist';
        buffer.writeln('Working directory: "$directory" ($directoryExistsMessage)');
        buffer.write(_stringifyPubEnv(pubEnvironment));
        throw io.ProcessException(
          exception.executable,
          exception.arguments,
          buffer.toString(),
          exception.errorCode,
        );
      }
      rethrow;
    }

    final int code = exitCode;
    final String result = code == 0 ? 'success' : 'failure';
    PubResultEvent(
      context: context.toAnalyticsString(),
      result: result,
      usage: _usage,
    ).send();

    if (code != 0) {
      final StringBuffer buffer = StringBuffer('$failureMessage\n');
      buffer.writeln('command: "${pubCommand.join(' ')}"');
      buffer.write(_stringifyPubEnv(pubEnvironment));
      buffer.writeln('exit code: $code');
      _logger.printTrace(buffer.toString());
      throwToolExit(null, exitCode: code);
    }
  }

  // For surfacing pub env in crash reporting
  String _stringifyPubEnv(Map<String, String> map, {String prefix = 'pub env'}) {
    if (map.isEmpty) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('$prefix: {');
    for (final MapEntry<String, String> entry in map.entries) {
      buffer.writeln('  "${entry.key}": "${entry.value}",');
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  @override
  Future<void> batch(
    List<String> arguments, {
    required PubContext context,
    String? directory,
    MessageFilter? filter,
    String failureMessage = 'pub failed',
    String? flutterRootOverride,
  }) async {
    final bool showTraceForErrors = await _botDetector.isRunningOnBot;

    String lastPubMessage = 'no message';
    String? filterWrapper(String line) {
      lastPubMessage = line;
      if (filter == null) {
        return line;
      }
      return filter(line);
    }

    if (showTraceForErrors) {
      arguments.insert(0, '--trace');
    }
    final Map<String, String> pubEnvironment = await _createPubEnvironment(context: context, flutterRootOverride: flutterRootOverride);
    final List<String> pubCommand = <String>[..._pubCommand, ...arguments];
    final int code = await _processUtils.stream(
        pubCommand,
        workingDirectory: directory,
        mapFunction: filterWrapper, // may set versionSolvingFailed, lastPubMessage
        environment: pubEnvironment,
      );

    String result = 'success';
    if (code != 0) {
      result = 'failure';
    }
    PubResultEvent(
      context: context.toAnalyticsString(),
      result: result,
      usage: _usage,
    ).send();

    if (code != 0) {
      final StringBuffer buffer = StringBuffer('$failureMessage\n');
      buffer.writeln('command: "${pubCommand.join(' ')}"');
      buffer.write(_stringifyPubEnv(pubEnvironment));
      buffer.writeln('exit code: $code');
      buffer.writeln('last line of pub output: "${lastPubMessage.trim()}"');
      throwToolExit(
        buffer.toString(),
        exitCode: code,
      );
    }
  }

  @override
  Future<void> interactively(
    List<String> arguments, {
    FlutterProject? project,
    required PubContext context,
    required String command,
    bool touchesPackageConfig = false,
    bool generateSyntheticPackage = false,
    PubOutputMode outputMode = PubOutputMode.all
  }) async {
    await _runWithStdioInherited(
      arguments,
      command: command,
      directory: _fileSystem.currentDirectory.path,
      context: context,
      outputMode: outputMode,
    );
    if (touchesPackageConfig && project != null) {
      await _updateVersionAndPackageConfig(project);
    }
  }

  /// The command used for running pub.
  late final List<String> _pubCommand = _computePubCommand();

  List<String> _computePubCommand() {
    // TODO(zanderso): refactor to use artifacts.
    final String sdkPath = _fileSystem.path.joinAll(<String>[
      Cache.flutterRoot!,
      'bin',
      'cache',
      'dart-sdk',
      'bin',
      'dart',
    ]);
    if (!_processManager.canRun(sdkPath)) {
      throwToolExit(
        'Your Flutter SDK download may be corrupt or missing permissions to run. '
        'Try re-downloading the Flutter SDK into a directory that has read/write '
        'permissions for the current user.'
      );
    }
    return <String>[sdkPath, 'pub', '--suppress-analytics'];
  }

  // Returns the environment value that should be used when running pub.
  //
  // Includes any existing environment variable, if one exists.
  //
  // [context] provides extra information to package server requests to
  // understand usage.
  Future<String> _getPubEnvironmentValue(PubContext pubContext) async {
    // DO NOT update this function without contacting kevmoo.
    // We have server-side tooling that assumes the values are consistent.
    final String? existing = _platform.environment[_kPubEnvironmentKey];
    final List<String> values = <String>[
      if (existing != null && existing.isNotEmpty) existing,
      if (await _botDetector.isRunningOnBot) 'flutter_bot',
      'flutter_cli',
      ...pubContext._values,
    ];
    return values.join(':');
  }

  /// There are 2 ways to get the pub cache location
  ///
  /// 1) Provide the _kPubCacheEnvironmentKey.
  /// 2) The pub default user-level pub cache.
  ///
  /// If we are using 2, check if there are pre-packaged packages in
  /// $FLUTTER_ROOT/.pub-preload-cache and install them in the user-level cache.
  String? _getPubCacheIfAvailable() {
    if (_platform.environment.containsKey(_kPubCacheEnvironmentKey)) {
      return _platform.environment[_kPubCacheEnvironmentKey];
    }
    _preloadPubCache();
    // Use pub's default location by returning null.
    return null;
  }

  /// Load any package-files stored in FLUTTER_ROOT/.pub-preload-cache into the
  /// pub cache if it exists.
  ///
  /// Deletes the [preloadCacheDir].
  void _preloadPubCache() {
    final String flutterRootPath = Cache.flutterRoot!;
    final Directory flutterRoot = _fileSystem.directory(flutterRootPath);
    final Directory preloadCacheDir = flutterRoot.childDirectory('.pub-preload-cache');
    if (preloadCacheDir.existsSync()) {
      /// We only want to inform about existing caches on first run of a freshly
      /// downloaded Flutter SDK. Therefore it is conditioned on the existence
      /// of the .pub-preload-cache dir.
      _informAboutExistingCaches();
      final Iterable<String> cacheFiles =
            preloadCacheDir
              .listSync()
              .map((FileSystemEntity f) => f.path)
              .where((String path) => path.endsWith('.tar.gz'));
      _processManager.runSync(<String>[..._pubCommand, 'cache', 'preload', ...cacheFiles]);
      _tryDeleteDirectory(preloadCacheDir, _logger);
    }
  }

  /// Issues a log message if there is an existing pub cache and or an existing
  /// Dart Analysis Server cache.
  void _informAboutExistingCaches() {
    final String? pubCachePath = _pubCacheDefaultLocation();
    if (pubCachePath != null) {
      final Directory pubCacheDirectory = _fileSystem.directory(pubCachePath);
      if (pubCacheDirectory.existsSync()) {
        _logger.printStatus('''
Found an existing Pub cache at $pubCachePath.
It can be repaired by running `dart pub cache repair`.
It can be reset by running `dart pub cache clean`.''');
      }
    }
    final String? home = _platform.environment['HOME'];
    if (home != null) {
      final String dartServerCachePath = _fileSystem.path.join(home, '.dartServer');
      if (_fileSystem.directory(dartServerCachePath).existsSync()) {
        _logger.printStatus('''
Found an existing Dart Analysis Server cache at $dartServerCachePath.
It can be reset by deleting $dartServerCachePath.''');
        }
      }
  }

  /// The default location of the Pub cache if the PUB_CACHE environment variable
  /// is not set.
  ///
  /// Returns null if the appropriate environment variables are unset.
  String? _pubCacheDefaultLocation () {
    if (_platform.isWindows) {
      final String? localAppData = _platform.environment['LOCALAPPDATA'];
      if (localAppData == null) {
        return null;
      }
      return _fileSystem.path.join(localAppData, 'Pub', 'Cache');
    } else {
      final String? home = _platform.environment['HOME'];
      if (home == null) {
        return null;
      }
      return _fileSystem.path.join(home, '.pub-cache');
    }
  }

  /// The full environment used when running pub.
  ///
  /// [context] provides extra information to package server requests to
  /// understand usage.
  Future<Map<String, String>> _createPubEnvironment({
    required PubContext context,
    String? flutterRootOverride,
    bool? summaryOnly = false,
  }) async {
    final Map<String, String> environment = <String, String>{
      'FLUTTER_ROOT': flutterRootOverride ?? Cache.flutterRoot!,
      _kPubEnvironmentKey: await _getPubEnvironmentValue(context),
      if (summaryOnly ?? false) 'PUB_SUMMARY_ONLY': '1',
    };
    final String? pubCache = _getPubCacheIfAvailable();
    if (pubCache != null) {
      environment[_kPubCacheEnvironmentKey] = pubCache;
    }
    return environment;
  }

  /// Updates the .dart_tool/version file to be equal to current Flutter
  /// version.
  ///
  /// Calls [_updatePackageConfig] for [project] and [project.example] (if it
  /// exists).
  ///
  /// This should be called after pub invocations that are expected to update
  /// the packageConfig.
  Future<void> _updateVersionAndPackageConfig(FlutterProject project) async {
    if (!project.packageConfigFile.existsSync()) {
      throwToolExit('${project.directory}: pub did not create .dart_tools/package_config.json file.');
    }
    final File lastVersion = _fileSystem.file(
      _fileSystem.path.join(project.directory.path, '.dart_tool', 'version'),
    );
    final File currentVersion = _fileSystem.file(
      _fileSystem.path.join(Cache.flutterRoot!, 'version'));
    lastVersion.writeAsStringSync(currentVersion.readAsStringSync());

    await _updatePackageConfig(project);
    if (project.hasExampleApp && project.example.pubspecFile.existsSync()) {
      await _updatePackageConfig(project.example);
    }
  }

  /// Update the package configuration file in [project].
  ///
  /// Creates a corresponding `package_config_subset` file that is used by the
  /// build system to avoid rebuilds caused by an updated pub timestamp.
  ///
  /// if `project.generateSyntheticPackage` is `true` then insert flutter_gen
  /// synthetic package into the package configuration. This is used by the l10n
  /// localization tooling to insert a new reference into the package_config
  /// file, allowing the import of a package URI that is not specified in the
  /// pubspec.yaml
  ///
  /// For more information, see:
  ///   * [generateLocalizations], `in lib/src/localizations/gen_l10n.dart`
  Future<void> _updatePackageConfig(FlutterProject project) async {
    final File packageConfigFile = project.packageConfigFile;
    final PackageConfig packageConfig = await loadPackageConfigWithLogging(packageConfigFile, logger: _logger);

    packageConfigFile.parent
      .childFile('package_config_subset')
      .writeAsStringSync(_computePackageConfigSubset(
        packageConfig,
        _fileSystem,
      ));

    if (!project.manifest.generateSyntheticPackage) {
      return;
    }
    if (packageConfig.packages.any((Package package) => package.name == 'flutter_gen')) {
      return;
    }

    // TODO(jonahwillams): Using raw json manipulation here because
    // savePackageConfig always writes to local io, and it changes absolute
    // paths to relative on round trip.
    // See: https://github.com/dart-lang/package_config/issues/99,
    // and: https://github.com/dart-lang/package_config/issues/100.

    // Because [loadPackageConfigWithLogging] succeeded [packageConfigFile]
    // we can rely on the file to exist and be correctly formatted.
    final Map<String, dynamic> jsonContents =
        json.decode(packageConfigFile.readAsStringSync()) as Map<String, dynamic>;

    (jsonContents['packages'] as List<dynamic>).add(<String, dynamic>{
      'name': 'flutter_gen',
      'rootUri': 'flutter_gen',
      'languageVersion': '2.12',
    });

    packageConfigFile.writeAsStringSync(json.encode(jsonContents));
  }

  // Subset the package config file to only the parts that are relevant for
  // rerunning the dart compiler.
  String _computePackageConfigSubset(PackageConfig packageConfig, FileSystem fileSystem) {
    final StringBuffer buffer = StringBuffer();
    for (final Package package in packageConfig.packages) {
      buffer.writeln(package.name);
      buffer.writeln(package.languageVersion);
      buffer.writeln(package.root);
      buffer.writeln(package.packageUriRoot);
    }
    buffer.writeln(packageConfig.version);
    return buffer.toString();
  }
}
