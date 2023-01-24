import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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


  Future<int> runWebdev(List<String> args) => Isolate.run(() => webdev.run(args),);

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
      process.stderr.listen(stderr.add);
    }
    if (pipeStdout || listen != null) {
      var pipe = pipeStdout;
      process.stdout.map(utf8.decode)
      ..listen(listen)
      ..where((event) => pipe = pipe && until != null && !until(event))
      .where((event)=>hide?.call(event) ?? true)
      .listen(stdout.write);
    }
    await watchExitCode(
      process.exitCode,
      onExit: onExit,
    );
  }
}
