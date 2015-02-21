import std.algorithm;
import std.file;
import std.path;
import std.stdio;
import std.range;

import fsdata;
import git;
import help;
import html;

int main(string[] args)
{
	import std.getopt;

	// Default output directory
	string outputDir = buildNormalizedPath(tempDir(), "vr-out");

	// Get command line options
	try {
		getopt(args,
			std.getopt.config.caseSensitive,
			"help|h", { writeAndSucceed(helpText); },
			"version|v", { writeAndSucceed(versionText); },
			"output|o", &outputDir);
	}
	catch (GetOptException ex) {
		writeAndFail(ex.msg, "\n\n", helpText);
	}

	// Expand home directory tildes as needed
	outputDir = outputDir.expandTilde();

	// Shave off program name
	args = args[1 .. $];

	// There should be one or two arguments
	if (args.length < 1 || args.length > 2)
		writeAndFail(helpText);
	else if (args.length == 1)
		args ~= "HEAD";

	assert(args.length == 2);

	enforceGitSetup();
	chdir(getRepoRoot());

	foreach (arg; args) {
		if (!commitExists(arg))
			writeAndFail(arg, " is not a known Git commit.");
	}

	if (args[0] == args[1])
		writeAndFail("Comparing the same version (", args[0], ") to itself is useless.");


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
	stderr.writeln("Writing report to ", absolutePath(outputDir));
	root.buildSite(outputDir);

	return 0;
}

private string helpText = q"EOS
Usage: versionreport [--output <output dir>] <commit 1> [<commit 2>]

where <commit 1> and <commit 2> are the two versions you want to compare.
If <commit 2> is not specified, <commit 1> is compared against HEAD
(the current commit).

Generates a static HTML report of the differences between provided git commits.
The commits are fed to git diff-tree, and its output is parsed to generate
the report.  The resulting site is written to the directory specified by
--output, or a "vr-out" directory in your temporary directory by default.

The output site is made of linked pages for each directory,
showing the amount of change made in each child file and directory.
Drilling down to changed files will show their Git diff.
Unlike git diff and git difftool, untracked and unchanged directories
and files are also listed - this was the main impetus for this project.

Options:

  --help, -h
    Display this help text.

  --version, -v
    Display version info.

  --output, -o <output directory>
    Write output to <output directory>.
    The directory will be created if it does not exist.
EOS";

private string versionText = q"EOS
Version Report v0.1, by Matt Kline, Fluke Networks
EOS";
