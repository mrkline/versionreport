import std.process;
import std.array;
import std.stdio;
import std.exception;
import std.string;
import std.typecons;

// A quick convenience value that redirects stdout and redirects stderr to it
enum stderrToStdout = Redirect.stdout | Redirect.stderrToStdout;

// Don't redirect anything
enum noRedirect = cast(Redirect)0;


/// Runs the provided command and gets its first line of output
string firstLineOf(S)(S command, Redirect flags = stderrToStdout)
	if (is(S == string) || is(S == string[]))
{
	auto pipes = pipeProcess(command, flags);
	scope(exit) {
		static if (is(S == string))
			enforce(wait(pipes.pid) == 0, command ~ "failed");
		else
			enforce(wait(pipes.pid) == 0, command.join(" ") ~ "failed");
	}

	auto lines = pipes.stdout.byLine;
	enforce(!lines.empty, "The command returned no output.");
	return lines.front.strip().idup;
}
