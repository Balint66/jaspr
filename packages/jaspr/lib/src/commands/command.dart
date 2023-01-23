import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
// ignore: implementation_imports
import 'package:webdev/src/webdev_command_runner.dart' as webdev show run;

import '../../jaspr.dart';

abstract class BaseCommand extends Command<void> {
  Set<Future<int>> activeProcesses = {};

  @override
  @mustCallSuper
  Future<void> run() async {
    ProcessSignal.sigint.watch().listen((signal) {
      shutdown();
    });
  }

  Future<void> waitActiveProcesses() {
    return Future.wait(activeProcesses);
  }

  Never shutdown([int exitCode = 1]) {
    // for (var process in activeProcesses) {
    // this would leave open files and ports broken
    // we should wait for https://github.com/dart-lang/sdk/issues/49234 to implement a better way
    // process.kill();
    // }
    exit(exitCode);
  }

  Future<int> runWebdev(List<String> args) => webdev.run(args);

  Future<String?> getEntryPoint(String? input) async {
    var entryPoints = [input, 'lib/main.dart', 'web/main.dart'];

    for (var path in entryPoints) {
      if (path == null) continue;
      var genPath = path.replaceFirst('.dart', '.g.dart');
      if (await File(genPath).exists()) {
        return genPath;
      } else if (await File(path).exists()) {
        return path;
      } else if (path == input) {
        return null;
      }
    }

    return null;
  }

  Future<void> watchExitCode(
    Future<int> exitCode, {
      void Function()? onExit,
    }
  ) async {
    activeProcesses.add(exitCode);
    final code = await exitCode;
    activeProcesses.remove(exitCode);
    if(code != 0){
      onExit?.call();
      shutdown();
    }
  }

  Future<void> watchProcess(
    Process process, {
    bool pipeStdout = true,
    bool pipeStderr = true,
    bool Function(String)? until,
    bool Function(String)? hide,
    void Function(String)? listen,
    void Function()? onExit,
  }) async {
    if (pipeStderr) {
      process.stderr.listen((event) => stderr.add(event));
    }
    if (pipeStdout || listen != null) {
      bool pipe = pipeStdout;
      process.stdout.listen((event) {
        String? _decoded;
        String decoded() => _decoded ??= utf8.decode(event);

        listen?.call(decoded());

        if (pipe && until != null) pipe = !until(decoded());
        if (!pipe || (hide?.call(decoded()) ?? false)) return;
        stdout.add(event);
      });
    }
    await watchExitCode(
      process.exitCode,
      onExit: onExit,
    );
  }
}
