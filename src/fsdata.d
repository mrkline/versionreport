import std.algorithm;
import std.exception;
import std.file;
import std.path;
import std.traits;

import git;

struct DirectoryEntry {
	/// Any directories contained in the directory
	DirectoryEntry[string] children;
	/// Any files contained in the directory
	FileEntry[string] files;

	// Info from files contained inside the directory.
	// Will be populated as we go through the Git diff.
	int totalChurn;

	/// Traverses to a given directory entry creating parent entries
	/// as needed on the way, similar to "mkdir -p".
	/// Returns a pointer to the desired directory entry.
	DirectoryEntry* traverseTo(S)(S path) if (isSomeString!S)
	in // preconditions
	{
		// The path to the subdirectory should obviously not be an absolute path
		assert(!path.isAbsolute());
	}
	body
	{
		if(path == ".")
			return &this;

		// Walk down the through the children, creating new ones if needed
		DirectoryEntry* current = &this;
		foreach(dir; pathSplitter(path)) {
			// Check if the current directory has the given child
			DirectoryEntry* next = dir in current.children;

			// If it doesn't, create it
			if (!next) {
				current.children[dir] = DirectoryEntry.init;
				next = &current.children[dir];
			}

			// Now advance to it
			current = next;
		}
		return current;
	}

	unittest
	{
		DirectoryEntry root;
		auto result = root.traverseTo("foo/bar/baz");
		auto foo = "foo" in root.children;
		assert(foo);
		auto bar = "bar" in foo.children;
		assert(bar);
		auto baz = "baz" in bar.children;
		assert(baz);
		assert(baz is result);
	}

	/// Finds a file at the given path,
	/// or throws an exception if one does not exist.
	/// Unlike traverseTo, this does not create anything.
	FileEntry* findOrInsertFile(S)(S path) if (isSomeString!S)
	in
	{
		assert(!path.isAbsolute());
	}
	body
	{
		DirectoryEntry* dir = traverseTo(dirName(path));

		auto fileName = baseName(path);

		FileEntry* ret = fileName in dir.files;
		if (!ret) {
			dir.files[fileName.idup] = FileEntry.init;
			ret = fileName in dir.files;
		}

		assert(ret);
		return ret;
	}

	unittest
	{
		DirectoryEntry root;
		root.traverseTo("foo/bar/baz").files["thefile"] = FileEntry.init;
		assert(root.findOrInsertFile("foo/bar/baz/thefile"));
		assert(root.findOrInsertFile("foo/doesn't exist yet"));
	}


	void sumChurn()
	{
		totalChurn = 0;

		foreach (ref child; children) {
			child.sumChurn();
			totalChurn += child.totalChurn;
		}

		// Sum the churn of the files that were changed.
		totalChurn += files.values
			.filter!(f => f.diff !is null)
			.map!(f => f.diff.churn)
			.sum;
	}
}

struct FileEntry {
	/**
	 * Git information if the file is tracked by Git,
	 * otherwise null.
	 *
	 * If performance becomes a concern,
	 * we could make this a Nullable instead of an actual pointer for cache-friendliness.
	 */
	DiffStat* diff;
	bool tracked;
}

/// Builds a tree of the repository directory
DirectoryEntry buildDirectoryTree()
{
	DirectoryEntry root;

	// Easy optimization:
	// We could avoid hashing our way down from the top each time
	// by keeping track of the current directory as we do the DFS and
	// stripping it from each dir as it comes in from dirEntires.
	foreach (entry; dirEntries(".", SpanMode.depth, false)) {
		// Normalize the path (usually just strip "./")
		// This matches Git output we'll be augmenting the tree with shortly.
		auto path = buildNormalizedPath(entry.name);

		// Skip the Git metadata
		if (pathSplitter(path).front == ".git")
			continue;

		if (entry.isDir) {
			root.traverseTo(path);
		}
		else {
			auto dir = root.traverseTo(dirName(path));
			dir.files[baseName(path)] = FileEntry.init;
		}
	}

	return root;
}
