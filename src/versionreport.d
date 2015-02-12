import std.algorithm;
import std.file;
import std.stdio;
import std.range;

import fsdata;
import getoptutils;
import git;
import help;

int main(string[] args)
{
	import std.getopt;

	getoptPreservingEOO(args,
		std.getopt.config.caseSensitive,
		"help|h", { writeAndSucceed(helpText); });

	// Shave off program name
	args = args[1 .. $];

	// If there are no args remaining, we're going to compare to HEAD
	// (same behavior as git diff)
	if (args.empty)
		args ~= "HEAD";

	enforceGitSetup();
	chdir(getRepoRoot());

	stderr.writeln("Building directory tree...");
	auto root = buildDirectoryTree();

	stderr.writeln("Marking files tracked by Git...");
	root.markTrackedFiles();

	stderr.writeln("Getting changes from Git...");
	DiffStat[] diffStats = diffIndex(args);

	// Apply those stats to their respective files in the tree
	foreach (stat; diffStats) {
		auto file = root.getFile(stat.path);
		file.diff = &stat;
	}

	// Sum up everything
	root.sumLinesChanged();

	return 0;
}

private string helpText = q"EOS
Usage: versionreport <commit(s)>

Options:

  --help, -h
    Display this help text.
EOS";
