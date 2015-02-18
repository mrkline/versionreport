import std.stdio;
import std.path;
import std.range;

import fsdata;

/*
 * This file writes the HTML output.
 * It's a tiny bit clunky at the moment but does its job.
 */

/// Info about the root directory for HTML output
/// and the root project directory, which may be useful as we traverse
/// the project writing out all our HTML.
struct RootInfo {
	const DirectoryEntry* rootEntry; ///< The root directory entry from the project
	string outputDirectory; ///< The directory to output HTML
}


/// Recursively builds an HTML report based on a given DirectoryEntry
/// and a path in which to place the report.
void buildSite(const ref DirectoryEntry entry, string outputDirectory)
{
	const RootInfo info = { &entry, outputDirectory };
	buildSiteRecursor(entry, "", info);
}

private:

/// Calculates and formats a string of the percentage of churn
/// for a given file or directory
string percentChurnString(int partial, int total)
{
	import std.string : format;

	double percent = cast(double)partial / cast(double)total * 100;

	// For now, cap displayed precision to whole percentages.
	if (percent > 0.0 && percent < 1.0)
		return "< 1%";
	else
		return format("%2.0f%%", percent);
}

/**
 * Recursively build the site
 * Params:
 *   entry = The current directory entry (these are recursively examined)
 *   relativePath = The path of said entry in the project
 *   rootInfo = The info about the root entry and our output path
 */
void buildSiteRecursor(in ref DirectoryEntry entry, string relativePath, in ref RootInfo rootInfo)
{
	import std.file : mkdirRecurse;

	string entryDirectory = buildNormalizedPath(rootInfo.outputDirectory, relativePath);
	mkdirRecurse(entryDirectory);

	// Write the page for this entry.
	writeDirectoryPage(entry, relativePath, rootInfo);

	// Write file pages for any files in this entry.
	foreach (name, file; entry.files) {
		string filePath = buildNormalizedPath(entryDirectory, name ~ ".html");
		writeFilePageIfNeeded(file, filePath);
	}

	// Recurse down for child entries.
	foreach (name, child; entry.children) {
		string relativeChildPath = buildNormalizedPath(relativePath, name);
		buildSiteRecursor(child, relativeChildPath, rootInfo);
	}
}

void writeFilePageIfNeeded(in ref FileEntry fe, string filePath)
{
	import std.string: translate;

	if (fe.diff is null)
		return;

	auto fout = File(filePath, "wb");

	with (fout) {
		writeln("<!DOCTYPE html>");
		writeln("<html>");
		writeln("<head>");
		writeln(`<meta charset="utf-8">`);
		writeln("<title>Version report</title>");
		writeln("</head>");
		writeln("<body>");
		writeln(`<a href="index.html">..</a>`);
		writeln("<pre><code>");
		try {
			string[dchar] escapeTable =
				['\'' : "&apos;", '"' : "&quot;", '&' : "&amp;", '<' : "&lt;", '>' : "&gt;"];

			writeln(translate(fe.diff.patch, escapeTable));
		}
		catch (core.exception.UnicodeException ex) {
			stderr.writeln("Warning: Unable to write file ", filePath, " because its diff contained invalid UTF-8");
			writeln("Diff could not be converted to HTML as it contained invalid UTF-8");
			return;
		}
		writeln("</code></pre>");
		writeln("</body>");
		writeln("</html>");
	}
}

void writeDirectoryPage(in ref DirectoryEntry entry, string relativePath, in ref RootInfo rootInfo)
{
	auto writer = DirectoryPageWriter(entry, relativePath, rootInfo);
	writer.write();
}

// Helper class to hold some state (such as the file handle and the root info)
// as we write out a directory page
struct DirectoryPageWriter {

	@disable this();

	this(const ref DirectoryEntry dir, string relative, const ref RootInfo ri)
	{
		assert(relative);
		string pagePath = buildNormalizedPath(ri.outputDirectory, relative, "index.html");
		fout = File(pagePath, "w");
		entry = &dir;
		relativePath = relative;
		rootInfo = &ri;
	}

	void write()
	{
		with (fout) { // Use fout.writeln, not std.stdio.writeln
			writeln("<!DOCTYPE html>");
			writeln("<html>");
			writeln("<head>");
			writeln(`<meta charset="utf-8">`);
			writeln("<title>", relativePath, "</title>");
			writeln("</head>");
			writeln("<body>");
			write("<h1>Version report");
			// If we're not in the root directory, put the path into the heading.
			if (!relativePath.empty)
				write(" for ", relativePath);
			writeln("</h1>");
			writeln("<hr/>");
			// If it's not the top directory, build a linked path
			if (entry !is rootInfo.rootEntry) {
				auto dirs = pathSplitter(relativePath).array;
				dirs = "project root" ~ dirs;
				foreach (idx, dir; dirs[0 .. $-1]) {
					// Build a path like "../../../" up to the given directory.
					write(`<a href="`, repeat("..", dirs.length - idx - 1).join("/"),
					                 `/index.html">`, dir, "</a>/");
				}
				// Cap it off with our current directory.
				writeln(dirs[$-1]);
			}
			writeEntryTable();
			writeln("</body>");
			writeln("</html>");
		}
	}

	void writeEntryTable()
	{
		with (fout) {
			writeln(`<table>`);
			writeln("  <tr>");
			writeln("    <th>Path</th>");
			writeln("    <th>Tracked</th>");
			writeln("    <th>Total lines changed</th>");
			writeln(`    <th colspan="2">Percent of total churn</th>`);
			writeln("  </tr>");
			foreach (name, child; entry.children)
				writeChildDirectoryRow(name, child);

			foreach (name, file; entry.files)
				writeFileRow(name, file);
			writeln("</table>");
		}
	}

	void writeChildDirectoryRow(string childName, const ref DirectoryEntry child)
	{
		immutable childChurn = child.totalChurn;
		immutable totalChurn = rootInfo.rootEntry.totalChurn;
		string pstring = percentChurnString(childChurn, totalChurn);

		with (fout) {
			writeln("  <tr>");
			writeln(`    <td><a href="`, childName, `/index.html">`, childName, "/</a></td>");
			writeln("    <td>", child.containsTrackedFiles ? "✓" : " ", "</td>");
			writeln("    <td>", child.totalChurn, "</td>");
			writeln("    <td>", pstring, "</td>");
			writeln(`    <td><progress value="`, childChurn, `" max="`, totalChurn, `"></progress>`);
			writeln("  </tr>");
		}
	}

	void writeFileRow(string fileName, const ref FileEntry fe)
	{
		immutable totalChurn = rootInfo.rootEntry.totalChurn;

		with (fout) {
			writeln("  <tr>");
			// We only write a page for a file if it has a diff
			if (fe.diff !is null) {
				immutable fileChurn = fe.diff.churn;
				string pstring = percentChurnString(fileChurn, totalChurn);
				writeln(`    <td><a href="`, fileName, `.html">`, fileName, "</a></td>");
				writeln("    <td>", fe.tracked ? "✓" : " ", "</td>");
				writeln("    <td>", fe.diff.churn, "</td>");
				writeln("    <td>", pstring, "</td>");
				writeln(`    <td><progress value="`, fileChurn, `" max="`, totalChurn, `"></progress>`);
			}
			// So, if it doesn't, zeroes across the board and no hyperlink.
			else {
				writeln("    <td>", fileName, "</td>");
				writeln("    <td>", fe.tracked ? "✓" : " ", "</td>");
				writeln("    <td>0</td>");
				writeln("    <td>0%</td>");
				writeln(`    <td><progress value="0" max="`, totalChurn, `"></progress>`);
			}
			writeln("  </tr>");
		}
	}

	File fout;
	const DirectoryEntry* entry;
	string relativePath;
	const RootInfo* rootInfo;
}
