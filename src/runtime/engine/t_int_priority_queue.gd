class_name TIntPriorityQueue
extends TPriorityQueue
## Port of TIntPriorityQueue<T : class> (Engine\Engine.Helferlein.DataStructures.pas:422): Int64 priorities,
## compared exactly (the server's delayed events).


func Compare(a, b) -> int:
	if a == b:
		return 0
	return -1 if a < b else 1
