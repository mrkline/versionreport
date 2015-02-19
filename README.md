## What is it?

versionreport is a simple tool that generates a static HTML report of the differences between provided Git commits.
The commits are fed to `git diff-tree`, and its output is parsed to generate the report.

The output site is made of linked pages for each directory,
showing the percentage of total change, or "churn", per directory.
Drilling down to changed files will show their Git diff.
Unlike `git diff` and `git difftool`, untracked and unchanged directories and files are also listed -
this was the main impetus for this project.

## What is there so far?

This is just a prototype.
The output is bare-bones HTML5 and lacking in CSS.
Progress bars are displayed using the new HTML5 `<progress>` tag, so IE9 and earlier are not supported
(use IE 10+ or some other browser).

## How do I use it?

Currently versionreport is a command line tool.
Add it to your [PATH](https://en.wikipedia.org/wiki/PATH_(variable)),
navigate to the directory of the Git repository you wish to make a report from,
then run it with

    versionreport <commit 1> <commit 2>

where `<commit 1>` and `<commit 2>` are the two versions you want to compare.
If `<commit 2>` is not specified, `<commit 1>` is compared against `HEAD` (the current commit).
Assuming versions are tagged in Git, you can view versions via `git tag`.

By default, versionreport will write the report to a `vr-out` directory
in your system's temporary directory. You can specify a different location with:

    versionreport -o <output directory> <commit 1> <commit 2>

or get additional information with

    versionreport --help

Once versionreport finishes, you can view the report by opening `index.html` in the output directory
using your web browser.

## How do I build it?

versionreport is written in [D](http://dlang.org/), for the primary reasons:

- D has a nice standard library that allows us to do everything this project requires
  (easily!) without any additional libraries.

- D is as expressive as something like Python while also offering advantages of a compiled language like C++,
  such as performance and compile-time type checks.
  This whole project clocks in at a bit over 500 lines of code, including help text.

Files for D's package manager, [DUB](http://code.dlang.org/), are provided, so if you have DUB installed
you can just run `dub build`. Otherwise you can build versionreport using the D compiler with

    dmd -release -ofversionreport src/*.d
