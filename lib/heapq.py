# heapq: heaps (priority queues) in a list, as Python's heapq module: heap[0] is the
# smallest item


def _up(heap, start, pos):
    item = heap[pos]
    while pos > start:
        parent = (pos - 1) // 2
        if item < heap[parent]:
            heap[pos] = heap[parent]
            pos = parent
        else:
            break
    heap[pos] = item


def _down(heap, pos):
    end = len(heap)
    item = heap[pos]
    while True:
        child = 2 * pos + 1
        if child >= end:
            break
        if child + 1 < end and heap[child + 1] < heap[child]:
            child += 1
        if heap[child] < item:
            heap[pos] = heap[child]
            pos = child
        else:
            break
    heap[pos] = item


def heappush(heap, item):
    heap.append(item)
    _up(heap, 0, len(heap) - 1)


def heappop(heap):
    """Remove and return the smallest item."""
    last = heap.pop()
    if heap:
        item = heap[0]
        heap[0] = last
        _down(heap, 0)
        return item
    return last


def heappushpop(heap, item):
    """Push item, then pop the smallest (faster than the two)."""
    if heap and heap[0] < item:
        item, heap[0] = heap[0], item
        _down(heap, 0)
    return item


def heapreplace(heap, item):
    """Pop the smallest, then push item."""
    smallest = heap[0]
    heap[0] = item
    _down(heap, 0)
    return smallest


def heapify(x):
    """Make the list x a heap, in place."""
    for i in range(len(x) // 2 - 1, -1, -1):
        _down(x, i)


def nsmallest(n, iterable, key=None):
    return sorted(iterable, key=key)[:n]


def nlargest(n, iterable, key=None):
    return sorted(iterable, key=key, reverse=True)[:n]
