@tool
class_name SegmentData
extends RefCounted

## Lightweight data container for one Bezier segment's OCCT graph.


## Holds everything belonging to one Bezier segment's result.
## Each segment produces its own independent graph, so graphs stay tiny.
class SegmentGraph:
	var graph: OclGraphHandle
	var solid: OclNodeId

	func _init(g: OclGraphHandle, s: OclNodeId):
		graph = g
		solid = s


## Holds a reusable sweep profile (built once, referenced by many segments).
## Future: when cross-graph copy/import is available, segments can import this
## profile instead of building their own.
class SweepProfile:
	var graph: OclGraphHandle
	var profile_id: OclNodeId

	func _init(g: OclGraphHandle, p: OclNodeId):
		graph = g
		profile_id = p
