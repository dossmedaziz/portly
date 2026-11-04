import 'dart:io';

/// Result of running an external command.
class CommandResult {
  const CommandResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
}

/// Thrown when the executable itself cannot be found.
class CommandNotFound implements Exception {
  const CommandNotFound(this.executable);
  final String executable;
  @override
  String toString() => '`$executable` not found';
}

/// Runs external commands. Swapped for a fake in tests so nothing real is
/// executed or killed.
abstract interface class CommandRunner {
  Future<CommandResult> run(String executable, List<String> arguments);
}

class ProcessCommandRunner implements CommandRunner {
  const ProcessCommandRunner();

  @override
  Future<CommandResult> run(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(executable, arguments);
      return CommandResult(
        result.exitCode,
        result.stdout as String,
        result.stderr as String,
      );
    } on ProcessException catch (e) {
      // errno 2 = ENOENT: the binary is missing.
      if (e.errorCode == 2) throw CommandNotFound(executable);
      rethrow;
    }
  }
}

/// pkexec exit codes when the user dismisses or fails the password prompt.
bool isPkexecCancelled(int exitCode) => exitCode == 126 || exitCode == 127;
