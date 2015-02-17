## What is it?

versionreport is a simple tool that generates a static HTML report of the differences between provided git commits.
The commits are fed to git diff-tree, and its output is parsed to generate the report.

The output site is made of linked pages for each directory,
showing the percentage of total change, or "churn", per directory.
Drilling down to changed files will show their Git diff.
Unlike git diff and git difftool, untracked and unchanged directories and files are also listed -
this was the main impetus for this project.

## What's there so far?

So far, this is just a prototype.
Output is quite simple and lacking in CSS.
