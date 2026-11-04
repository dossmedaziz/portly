import 'package:portly/core/command_runner.dart';

/// Records commands and answers them from a script instead of running them.
class FakeRunner implements CommandRunner {
  FakeRunner(this.handler);

  final CommandResult Function(String executable, List<String> args) handler;
  final calls = <List<String>>[];

  @override
  Future<CommandResult> run(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    return handler(executable, arguments);
  }
}

CommandResult ok([String stdout = '']) => CommandResult(0, stdout, '');
CommandResult failed(int code, [String stderr = '']) =>
    CommandResult(code, '', stderr);
