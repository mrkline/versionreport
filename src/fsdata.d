import std.algorithm;
import std.exception;
import std.file;
import std.path;
import std.traits;

import git;

/// Represents a directory in the analyzed project
struct DirectoryEntry {
	/// Any directories contained in the directory
	DirectoryEntry[string] children;
	/// Any files contained in the directory
	FileEntry[string] files;

	// Info from files contained inside the directory.
	// Will be populated as we go through the Git diff.
	int totalChanges;
	bool containsTrackedFiles;

	/// Traverses to a given directory entry creating parent entries
	/// as needed on the way, similar to "mkdir -p".
	/// Returns a pointer to the desired directory entry.
	DirectoryEntry* traverseTo(in char[] path)
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
	/// or creates one if it does not exist.
	FileEntry* findOrInsertFile(in char[] path)
	in
	{
		assert(!path.isAbsolute());
	}
	body
	{
		DirectoryEntry* dir = traverseTo(dirName(path));

		auto fileName = baseName(path);

		FileEntry* ret = fileName in dir.files;
		// Create one if it does not exist
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


	/// Recurisvely gets the total change and sets the tracked flag
	/// for this and all child directories.
	void propagateStats()
	{
		totalChanges = 0;

		foreach (ref child; children) {
			child.propagateStats();
			totalChanges += child.totalChanges;
		}

		// Sum the change of the files that were changed.
		totalChanges += files.values
			.filter!(f => f.diff !is null)
			.map!(f => f.diff.changeCount)
			.sum;

		// We contain tracked files if any child directory does
		// or any file in our directory is tracked.
		containsTrackedFiles = any!(c => c.containsTrackedFiles)(children.values) ||
			any!(f => f.tracked)(files.values);
	}
}

/// Represents a file in the analyzed project
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

		// TODO: Possibly honor the .gitignore file?

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
