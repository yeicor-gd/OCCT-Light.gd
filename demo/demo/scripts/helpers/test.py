#!/usr/bin/env python3
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

pattern = re.compile(
    r'''static func _dump_edge\(graph, edge:int, indent:String, visited, do_print: bool = true\):\n\nif visited\.edge\.has\(edge\):\n\treturn''',
    re.MULTILINE,
)

replacement = r'''static func _dump_edge(graph, edge:int, indent:String, visited, do_print: bool = true):

	var already_seen := visited.edge.has(edge)

	if !already_seen:
		visited.edge[edge] = true'''

text, n = pattern.subn(replacement, text)

if n != 1:
    raise RuntimeError(f"Expected to patch exactly one _dump_edge(), patched {n}")

pattern = re.compile(
r'''if do_print:\n\t\tvar boundary := OclInt32\.new\(\)''')

replacement = r'''if already_seen:
		visited.vertex[sv.bits] = true
		visited.vertex[ev.bits] = true
		return

	if do_print:
		var boundary := OclInt32.new()'''

text, n = pattern.subn(replacement, text, count=1)

if n != 1:
    raise RuntimeError("Failed second patch")

path.write_text(text)
print("Patched", path)
