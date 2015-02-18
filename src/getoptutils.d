import std.algorithm;
import std.getopt;
import std.range;

// Find the end of options (EOO) string and only pass getopt whatever is to its left.
// This is to get around the fact that getopt will remove the EOO, which we don't
// always want (especially if we are passing these args to another program.
// I've opened a pull request with the D standard library to avoid having to do this,
// and it has been merged and should be in the next release of D (version 2.067):
// https://github.com/D-Programming-Language/phobos/pull/2974
void getoptPreservingEOO(T...)(ref string[] args, T opts)
{

	auto remaining = args.find(endOfOptions); // Slices bits off until we hit EOO
	args = args[0 .. $ - remaining.length]; // Slice off EOO and everything after
	getopt(args, opts);
	// Rejoin everything after.
	args = args ~ remaining;
}

// Ensure normal behavior int the absence of an EOO
unittest
{
	string[] args = ["./program", "--foo", "--bar", "--baz"];
	bool foo, bar, baz;
	getoptPreservingEOO(args,
		"foo", &foo,
		"bar", &bar,
		"baz", &baz);
	assert(args == ["./program"]);
}

// Test with an EOO
unittest
{
	string[] args = ["./program", "--foo", "--", "--bar", "--baz"];
	bool foo;
	getoptPreservingEOO(args,
		"foo", &foo);
	assert(args == ["./program", "--", "--bar", "--baz"]);
}
