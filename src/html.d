import std.stdio;
import std.path;

import fsdata;

/// Info about the root directory for HTML output
/// and the root project directory, which may be useful as we traverse
/// the project writing out all our HTML.
struct RootInfo {
	DirectoryEntry* rootEntry; ///< The root directory entry from the project
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
void buildSiteRecursor(const ref DirectoryEntry entry, string relativePath, const ref RootInfo rootInfo)
{
	import std.file : mkdirRecurse;

	string entryDirectory = buildNormalizedPath(rootInfo.outputDirectory, relativePath);
	mkdirRecurse(entryDirectory);

	writeDirectoryPage(entry, relativePath, rootInfo);
	foreach (name, file; entry.files) {
		string filePath = buildNormalizedPath(entryDirectory, name ~ ".html");
		writeFilePageIfNeeded(file, filePath);
	}

	foreach (name, child; entry.children) {
		string relativeChildPath = buildNormalizedPath(relativePath, name);
		buildSiteRecursor(child, relativeChildPath, rootInfo);
	}
}

void writeFilePageIfNeeded(const ref FileEntry fe, string filePath)
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
			stderr.writeln("Warning: Unable to write file ", filePath, ".html because its diff contained invalid UTF-8");
			writeln("Diff could not be converted to HTML as it contained invalid UTF-8");
			return;
		}
		writeln("</code></pre>");
		writeln("</body>");
		writeln("</html>");
	}
}

void writeDirectoryPage(const ref DirectoryEntry entry, string relativePath, const ref RootInfo rootInfo)
{
	auto writer = DirectoryPageWriter(entry, relativePath, rootInfo);
	writer.write();
}

// Just used to hold some state (mostly the file handle and the total churn)
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
		with (fout) {
			writeln("<!DOCTYPE html>");
			writeln("<html>");
			writeln("<head>");
			writeln(`<meta charset="utf-8">`);
			writeln("<title>", relativePath, "</title>");
			writeln("</head>");
			writeln("<body>");
			// If it's not the top directory
			// add a ..
			if (entry !is rootInfo.rootEntry)
				writeln(`<a href="../index.html">..</a>`);
			writeEntryTable();
			writeln("</body>");
			writeln("</html>");
		}
	}

	void writeEntryTable()
	{
		with (fout) {
			writeln(`<table cellpadding="1">`);
			writeln("  <tr>");
			writeln("    <th>Path</th>");
			writeln("    <th>Percent of total churn</th>");
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
		with (fout) {
			writeln("  <tr>");
			writeln(`    <td><a href="`, childName, `/index.html">`, childName, "/</a></td>");
			string pstring = percentChurnString(child.totalChurn, rootInfo.rootEntry.totalChurn);
			writeln("    <td>", pstring, "</td>");
			writeln("  </tr>");
		}
	}

	void writeFileRow(string fileName, const ref FileEntry fe)
	{
		with (fout) {
			writeln("  <tr>");
			// We only write a page for a file if it has a diff
			if (fe.diff !is null) {
			writeln(`    <td><a href="`, fileName, `.html">`, fileName, "</a></td>");
			string pstring = percentChurnString(fe.diff.churn, rootInfo.rootEntry.totalChurn);
			writeln("    <td>", pstring, "</td>");
			}
			else {
			writeln("    <td>", fileName, "</td>");
			writeln("    <td>0%</td>");
			}
			writeln("  </tr>");
		}
	}

	File fout;
	const DirectoryEntry* entry;
	string relativePath;
	const RootInfo* rootInfo;
}
