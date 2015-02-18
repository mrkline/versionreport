import std.algorithm;
import std.file;
import std.path;
import std.stdio;
import std.range;

import fsdata;
import getoptutils;
import git;
import help;
import html;

int main(string[] args)
{
	import std.getopt;

	// Default output directory
	string outputDir = buildNormalizedPath(tempDir(), "vr-out");

	// Get command line options
	getoptPreservingEOO(args,
		std.getopt.config.caseSensitive,
		"help|h", { writeAndSucceed(helpText); },
		"output|o", &outputDir);

	// Expand home directory tildes as needed
	outputDir = outputDir.expandTilde();

	// Shave off program name
	args = args[1 .. $];

	// If there are no args remaining, we're going to compare to HEAD
	// (similar to git show)
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
	foreach (ref stat; diffStats) {
		auto file = root.findOrInsertFile(stat.path);
		// In almost all cases, this should already be set via markTrackedFiles above.
		// However, in the case where a file was deleted in the Git log,
		// the file will will have just been created by findOrInsert and will have default
		// values, so indicate that it is tracked (since it was deleted in Git history).
		file.tracked = true;
		file.diff = &stat;
	}

	// Recursively sum the lines of change in directories and propagate other stats up.
	root.propagateStats();

	// Build the output.
	root.buildSite(outputDir);

	return 0;
}

private string helpText = q"EOS
Usage: versionreport [--output <output dir>] <commits>

Generates a static HTML report of the differences between provided git commits.
The commits are fed to git diff-tree, and its output is parsed to
generate the report.
The resulting site is written to the directory specified by --output,
or a "vr-out" directory in your temporary directory by default.

The output site is made of linked pages for each directory,
showing the percentage of total change, or "churn", per directory.
Drilling down to changed files will show their Git diff.
Unlike git diff and git difftool, untracked and unchanged directories
and files are also listed - this was the main impetus for this project.

Options:

  --help, -h
    Display this help text.

  --output, -o <output directory>
    Write output to <output directory>.
    The directory will be created if it does not exist.
EOS";
