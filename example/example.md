# Example

From the root of any Dart package or pub workspace:

```sh
dart pub global activate dependency_graph
dependency_graph . build/dependency_graph/index.html
# 41 packages, 760 files, 3788 edges, 208 external libraries → …/build/dependency_graph/index.html
```

Then open the page and double-click a package to see its files.
