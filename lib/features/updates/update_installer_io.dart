import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'update_contracts.dart';
import 'update_downloader_io.dart';
import 'update_install_scripts.dart';
import 'update_release.dart';

UpdateInstaller createUpdateInstaller() => NativeUpdateInstaller();

class NativeUpdateInstaller implements UpdateInstaller {
  bool _disposed = false;
  bool _exitRequested = false;
  UpdateDownloader? _downloader;
  Directory? _helperStage;

  @override
  UpdateTarget? get target => switch (Abi.current()) {
    Abi.windowsX64 => const UpdateTarget(UpdateOS.windows, UpdateArch.x64),
    Abi.windowsArm64 => const UpdateTarget(UpdateOS.windows, UpdateArch.arm64),
    Abi.linuxX64 => const UpdateTarget(UpdateOS.linux, UpdateArch.x64),
    Abi.linuxArm64 => const UpdateTarget(UpdateOS.linux, UpdateArch.arm64),
    _ => null,
  };

  @override
  String? get unavailableReason => Platform.isLinux &&
      (Platform.environment['APPIMAGE'] ?? '').isEmpty
      ? 'Automatic updates require the official Linux AppImage. Use your package manager for other distributions.'
      : null;

  @override
  Future<String?> acknowledgeStartup() async {
    final warning = Platform.environment['POMODOIST_UPDATE_ERROR'] == '1'
        ? 'The previous update failed. Your previous version was restored. Check for updates to retry.' : null;
    final marker = Platform.environment['POMODOIST_UPDATE_READY_FILE'];
    if (marker == null || !p.isAbsolute(marker) || p.basename(marker) != 'started') return warning;
    final stage = Directory(p.dirname(marker));
    if (!p.basename(stage.path).startsWith('.pomodoist-update-') || !await stage.exists()) return warning;
    // Do not let an arbitrary launch environment redirect the health marker.
    if (await stage.resolveSymbolicLinks() != stage.absolute.path) return warning;
    await File(marker).writeAsString('started\n', flush: true);
    unawaited(_cleanSuccessfulStage(stage));
    return warning;
  }

  Future<void> _cleanSuccessfulStage(Directory stage) async {
    // The helper owns the staging directory until it has released its lock and
    // completed backup cleanup. Failed updates retain logs/backups for recovery.
    try {
      for (var attempt = 0; attempt < 90 && !_disposed; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final result = File(p.join(stage.path, 'result'));
        if (!await result.exists()) continue;
        if ((await result.readAsString()).trim() == 'success') {
          await Future<void>.delayed(const Duration(seconds: 2));
          await stage.delete(recursive: true);
        }
        return;
      }
    } catch (_) { /* Cleanup must never interrupt normal application startup. */ }
  }

  Map<String, String> _helperEnvironment() {
    final environment = Map<String, String>.from(Platform.environment);
    for (final name in const ['APPIMAGE', 'APPDIR', 'ARGV0', 'OWD',
      'LD_LIBRARY_PATH', 'LD_PRELOAD', 'GSETTINGS_SCHEMA_DIR', 'GIO_EXTRA_MODULES',
      'GDK_PIXBUF_MODULE_FILE', 'GTK_PATH', 'POMODOIST_UPDATE_READY_FILE',
      'POMODOIST_UPDATE_ERROR']) {
      environment.remove(name);
    }
    return environment;
  }

  @override
  Future<void> install(UpdateOffer offer, UpdateProgress progress) async {
    final platform = target;
    if (_disposed || platform == null || unavailableReason != null) {
      throw UpdateFailure(unavailableReason ?? 'Desktop updating is unavailable.');
    }
    if (!platform.artifactNames.contains(offer.asset.name)) {
      throw const UpdateFailure('The update does not match this platform and architecture.');
    }
    final executable = platform.os == UpdateOS.linux
        ? await File(Platform.environment['APPIMAGE']!).resolveSymbolicLinks()
        : Platform.resolvedExecutable;
    if (platform.os == UpdateOS.windows && p.basename(executable).toLowerCase() != 'pomodoist.exe') {
      throw const UpdateFailure('Use an installed Pomodoist desktop build to update.');
    }
    // Sibling staging keeps Linux rename atomic and Windows rollback on the same
    // volume. Creating it also checks permissions before downloading anything.
    final parent = Directory(platform.os == UpdateOS.windows
        ? p.dirname(p.dirname(executable)) : p.dirname(executable));
    Directory? stage;
    var helperStarted = false;
    final downloader = UpdateDownloader();
    _downloader = downloader;
    try {
      stage = await parent.createTemp('.pomodoist-update-');
      if (platform.os == UpdateOS.linux) {
        final chmod = await Process.run('/bin/chmod', ['700', stage.path]);
        if (chmod.exitCode != 0) throw const UpdateFailure('Could not secure update staging directory.');
      }
      final payload = File(p.join(stage.path, offer.asset.name));
      final hash = await downloader.download(offer, payload, progress);
      if (_disposed) throw const UpdateFailure('Update cancelled.');
      progress(UpdatePhase.installing, null);
      final windows = platform.os == UpdateOS.windows;
      final script = File(p.join(stage.path, windows ? 'install.ps1' : 'install.sh'));
      await script.writeAsString(windows ? windowsUpdateScript : linuxUpdateScript, flush: true);
      final command = windows
          ? p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows',
              'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
          : '/bin/sh';
      final arguments = windows
          ? ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
              '-WindowStyle', 'Hidden', '-File', script.path,
              '-ParentProcessId', '$pid', '-ApplicationPath', executable,
              '-InstallerPath', payload.path, '-Sha256', hash]
          : [script.path, '$pid', executable, payload.path, hash];
      await Process.start(command, arguments, mode: ProcessStartMode.detached,
        workingDirectory: stage.path, environment: _helperEnvironment(),
        includeParentEnvironment: false);
      helperStarted = true;
      _helperStage = stage;
      final ready = File(p.join(stage.path, 'ready'));
      for (var attempt = 0; attempt < 150 && !await ready.exists(); attempt++) {
        if (_disposed || await File(p.join(stage.path, 'result')).exists()) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (_disposed || !await ready.exists()) {
        throw const UpdateFailure('The installer could not prepare the update. The application was not changed.');
      }
      _exitRequested = true;
      final response = await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
      if (response == AppExitResponse.cancel) {
        _exitRequested = false;
        throw const UpdateFailure('Restart cancelled. Your current application is still running.');
      }
    } on FileSystemException {
      _exitRequested = false;
      throw const UpdateFailure('The update location is not writable or has insufficient disk space.');
    } catch (_) {
      _exitRequested = false;
      rethrow;
    } finally {
      downloader.dispose();
      _downloader = null;
      // Normal successful handoff exits the process and never reaches here.
      if (stage != null && !_exitRequested) {
        if (helperStarted) {
          try { await File(p.join(stage.path, 'cancel')).writeAsString('cancel\n', flush: true); }
          catch (_) { /* The helper also times out without a graceful exit. */ }
        } else {
          try { await stage.delete(recursive: true); } catch (_) { /* Best effort. */ }
        }
      }
      _helperStage = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _downloader?.dispose();
    final stage = _helperStage;
    if (stage != null && !_exitRequested) {
      try { File(p.join(stage.path, 'cancel')).writeAsStringSync('cancel\n', flush: true); }
      catch (_) { /* No executable is replaced while the parent remains alive. */ }
    }
  }
}
