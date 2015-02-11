import std.algorithm;
import std.conv;
import std.exception;
import std.process;
import std.range;
import std.stdio;
import std.string;

import fsdata;
import processutils;

struct DiffStat {
	int linesAdded;
	int linesRemoved;
	string path;
	string patch;
}

bool canFindGit()
{
	return execute(["git", "--version"]).status == 0;
}

void enforceGitFound()
{
	enforce(canFindGit(), "Cannot find Git. Please make sure it is in the PATH.");
}

bool isInRepo()
{
	return execute(["git", "status"]).status == 0;
}

void enforceInRepo()
{
	enforce(isInRepo(), "The current directory is not in a Git repository.");
}

/// Enforces that we can find git and we're in a repo
void enforceGitSetup()
{
	enforceGitFound();
	enforceInRepo();
}

/// Gets the root directory of the git repo we are in.
string getRepoRoot()
{
	return firstLineOf(["git", "rev-parse", "--show-toplevel"]);
}

/// Calls git diff-index with --numstat and --patch
/// in order to get the number of lines changed per file as well as the patch.
/// Returns an array of this information (see DiffStat)
DiffStat[] diffIndex(string[] args)
{
	auto pipes = pipeProcess(["git", "diff-index", "--numstat", "--patch"] ~ args,
	                         Redirect.stdout);
	// Make sure to wait for the process on the way out
	scope(exit) enforce(wait(pipes.pid) == 0, "git diff-index failed");
	// If we're leaving early due to an exception,
	// kill the process so it doesn't hang on a full pipe.
	scope(failure) { kill(pipes.pid); wait(pipes.pid); }

	DiffStat[] ret;

	auto lines = pipes.stdout.byLine(KeepTerminator.yes);

	if (lines.empty)
		return ret;

	// numstat lines and patches are separated by a newline
	while (!lines.front.strip().empty) {
		ret ~= parseNumstatLine(lines.front);
		lines.popFront();
	}

	// Pop the diff line and we should be set to go with the patches
	lines.popFront();
	foreach (ref stat; ret) {
		enforce(!lines.empty, "Unexpected end of git diff-index output");
		stat.appendPatchToStat(lines);
	}

	return ret;
}

/// Annotates files tracked by Git
void markTrackedFiles(ref DirectoryEntry root)
{
	auto pipes = pipeProcess(["git", "ls-files"], Redirect.stdout);
	// Make sure to wait for the process on the way out
	scope(exit) enforce(wait(pipes.pid) == 0, "git ls-files failed");
	// If we're leaving early due to an exception,
	// kill the process so it doesn't hang on a full pipe.
	scope(failure) { kill(pipes.pid); wait(pipes.pid); }

	foreach(file; pipes.stdout.byLine)
		root.getFile(file).tracked = true;
}

private:

pure DiffStat parseNumstatLine(const char[] line)
{
	auto tokens = splitter(line).array;
	enforce(tokens.length == 3,
	        "Unexpected format for numstat line from git diff-index\n"
	        "(got " ~ line ~ ")");
	DiffStat newStat;
	newStat.linesAdded = tokens[0].to!int;
	newStat.linesRemoved = tokens[1].to!int;
	newStat.path = tokens[2].idup;
	return newStat;
}

unittest
{
	DiffStat ds = parseNumstatLine("25 6 toFour");
	assert(ds.linesAdded == 25);
	assert(ds.linesRemoved == 6);
	assert(ds.path == "toFour");

	ds = parseNumstatLine("25\t6\ttoFour"); // Actual git output is tabs
	assert(ds.linesAdded == 25);
	assert(ds.linesRemoved == 6);
	assert(ds.path == "toFour");

	assertThrown(parseNumstatLine("25 NaN nope"));
	assertThrown(parseNumstatLine("25 6 2 4 Chicago"));
}

/*
 * A diff looks like this:
 * diff --git a/foo b/foo
 * index 2f39c25..c6ad002 100644
 * --- a/foo
 * +++ b/foo
 * <diffs here>
 */
void appendPatchToStat(DL)(ref DiffStat ds, DL diffLines)
	if (isInputRange!DL)
in // preconditions
{
	assert(!diffLines.empty);
}
body
{
	auto firstLineTokens = splitter(diffLines.front);
	// Ensure we're at the head of a diff
	// (the line should start with "diff --git"
	enforce(firstLineTokens.front == "diff",
	        "Unexpected line contents for the start of a diff\n"
	        "(got " ~ firstLineTokens.front ~ ")");
	firstLineTokens.popFront();

	enforce(firstLineTokens.front == "--git",
	        "Unexpected line contents for the start of a diff\n"
	        "(got " ~ firstLineTokens.front ~ ")");
	firstLineTokens.popFront();

	// Strip the a/ and ensure it matches the current path
	enforce(firstLineTokens.front[2 .. $] == ds.path, "Got " ~ firstLineTokens.front[2 .. $]);

	// K, move over the line and keep going until we hit the start of the next diff
	ds.patch ~= diffLines.front;
	diffLines.popFront();

	// The next time we see a line in the form of
	// "diff --git ...",
	// it's time to stop.
	while (!diffLines.empty && !diffLines.front.startsWith("diff --git")) {
		ds.patch ~= diffLines.front;
		diffLines.popFront();
	}
}

unittest
{
	string[] testDiff = [
		"diff --git a/foo b/foo\n",
		"index 2f39c25..c6ad002 100644\n",
		"--- a/foo\n",
		"+++ b/foo\n",
		"<diffs here>\n"];

	DiffStat ds = parseNumstatLine("25 6 foo");
	ds.appendPatchToStat(testDiff);
	assert(ds.patch == testDiff.join(), "Got\n" ~ ds.patch);
}
