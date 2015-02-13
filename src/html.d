import std.stdio;

import fsdata;

void buildSite(const ref DirectoryEntry entry, string rootSaveDirectory)
{
	buildSiteRecursor(entry, rootSaveDirectory, entry);
}

private:

string percentChurnString(int partial, int total)
{
	import std.string : format;

	double percent = cast(double)partial / cast(double)total * 100;
	if (percent > 0.0 && percent < 1.0)
		return "< 1%";
	else
		return format("%2.0f%%", percent);
}

void buildSiteRecursor(const ref DirectoryEntry entry, string directory, const ref DirectoryEntry re)
{
	writeDirectoryPage(entry, directory, re);
	foreach (name, file; entry.files) {
		writeFilePageIfNeeded(file, directory ~ "/" ~ name);
	}

	foreach (name, child; entry.children)
		buildSiteRecursor(child, directory ~ "/" ~ name, re);
}

void writeFilePageIfNeeded(const ref FileEntry fe, string filePath)
{
	import std.string: translate;

	if (fe.diff is null)
		return;

	string[dchar] escapeTable =
		['\'' : "&apos;", '"' : "&quot;", '&' : "&amp;", '<' : "&lt;", '>' : "&gt;"];

	auto fout = File(filePath ~ ".html", "wb");

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
		writeln(translate(fe.diff.patch, escapeTable));
		writeln("</code></pre>");
		writeln("</body>");
		writeln("</html>");
	}
}

void writeDirectoryPage(const ref DirectoryEntry entry, string directoryPath, const ref DirectoryEntry re)
{
	import std.file : mkdirRecurse;

	mkdirRecurse(directoryPath);
	auto writer = DirectoryPageWriter(&entry, directoryPath ~ "/index.html", &re);
	writer.write();
}

// Just used to hold some state (mostly the file handle and the total churn)
// as we write out a directory page
struct DirectoryPageWriter {

	@disable this();

	this(const DirectoryEntry* dir, string filePath, const DirectoryEntry* re)
	in
	{
		import std.range : empty;

		assert(dir !is null);
		assert(!filePath.empty);
		assert(re !is null);
	}
	body
	{
		fout = File(filePath, "w");
		entry = dir;
		rootEntry = re;
	}

	void write()
	{
		with (fout) {
			writeln("<!DOCTYPE html>");
			writeln("<html>");
			writeln("<head>");
			writeln(`<meta charset="utf-8">`);
			writeln("<title>Version report</title>");
			writeln("</head>");
			writeln("<body>");
			// If it's not the top directory
			// add a ..
			if (entry !is rootEntry)
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
			string pstring = percentChurnString(child.totalChurn, rootEntry.totalChurn);
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
			string pstring = percentChurnString(fe.diff.churn, rootEntry.totalChurn);
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
	const DirectoryEntry* rootEntry;
}
