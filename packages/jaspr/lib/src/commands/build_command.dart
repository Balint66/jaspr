import 'dart:async';
import 'dart:io';

import 'command.dart';

class BuildCommand extends BaseCommand {
  BuildCommand() {
    argParser.addOption(
      'input',
      abbr: 'i',
      help: 'Specify the input file for the web app',
      defaultsTo: 'lib/main.dart',
    );
    argParser.addFlag(
      'ssr',
      defaultsTo: true,
      help: 'Optionally disables server-side rendering and runs as a pure client-side app.',
    );
    argParser.addOption(
      'target',
      abbr: 't',
      allowed: ['aot-snapshot', 'exe', 'jit-snapshot'],
      allowedHelp: {
        'aot-snapshot': 'Compile Dart to an AOT snapshot.',
        'exe': 'Compile Dart to a self-contained executable.',
        'jit-snapshot': 'Compile Dart to a JIT snapshot.',
      },
      defaultsTo: 'exe',
    );
  }

  @override
  String get description => 'Performs a single build on the specified target and then exits.';

  @override
  String get name => 'build';

  @override
  Future<void> run() async {
    await super.run();

    String? entryPoint = await getEntryPoint(argResults!['input']);

    //fail fast if there is no entry point
    if (entryPoint == null) {
      print("Cannot find entry point. Create a main.dart in lib/ or web/, or specify a file using --input.");
      shutdown(1);
    }

    var useSSR = argResults!['ssr'] as bool;

    if (useSSR) {
      var dir = Directory('build');
      if (!await dir.exists()) {
        await dir.create();
      }
    }

    var webProcess = runWebdev(['build', '--output=web:build${useSSR ? '/web' : ''}', '--', '--define=build_web_compilers:entrypoint=dart2js_args=["-Djaspr.flags.release=true"]']);

    var webResult = watchExitCode(webProcess);
    if (useSSR) {
      unawaited(webResult);
    } else {
      return webResult;
    }

    var process = await Process.start(
      'dart',
      ['compile', argResults!['target'], entryPoint, '-o', './build/app', '-Djaspr.flags.release=true'],
    );

    unawaited(watchProcess(process));

    await waitActiveProcesses();
  }
}
