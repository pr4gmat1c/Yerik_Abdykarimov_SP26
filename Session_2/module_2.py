from itertools import product
from typing import Any, Dict, List, Tuple


def task_1(data_1: Dict[str, int], data_2: Dict[str, int]):
    # Start with a copy of the first dict so we don't mutate the original
    result = dict(data_1)

    # Walk through the second dict — if the key already exists, add to it; otherwise just insert
    for key, value in data_2.items():
        result[key] = result.get(key, 0) + value

    return result


def task_2():
    # One-liner: keys are 1..15, values are their squares
    return {n: n ** 2 for n in range(1, 16)}


def task_3(data: Dict[Any, List[str]]):
    # product(*data.values()) gives every possible combo across all lists
    # e.g. ['a','b'] x ['c','d'] → ('a','c'), ('a','d'), ('b','c'), ('b','d')
    # "".join() collapses each tuple into a single string like "ac", "ad" etc.
    return ["".join(combo) for combo in product(*data.values())]


def task_4(data: Dict[str, int]):
    if not data:
        return []

    # Sort keys by their values in descending order, grab the top 3
    # If the dict has fewer than 3 entries, [:3] safely returns whatever's there
    return sorted(data, key=lambda k: data[k], reverse=True)[:3]


def task_5(data: List[Tuple[Any, Any]]) -> Dict[str, List[int]]:
    result = {}

    for key, value in data:
        # If we haven't seen this key before, initialise an empty list for it
        if key not in result:
            result[key] = []
        result[key].append(value)

    return result


def task_6(data: List[Any]):
    seen = []

    for item in data:
        # Can't use a set here — it would collapse 2 and 2.0 into one entry
        # Plain list membership check preserves type distinctions like "2" vs 2 vs 2.0
        if item not in seen:
            seen.append(item)

    return seen


def task_7(words: List[str]) -> str:
    if not words:
        return ""

    # Use the first word as the starting candidate for the common prefix
    prefix = words[0]

    for word in words[1:]:
        # Keep trimming the tail of the prefix until the current word starts with it
        # If we trim all the way to empty, there's no common prefix at all
        while not word.startswith(prefix):
            prefix = prefix[:-1]
            if not prefix:
                return ""

    return prefix


def task_8(haystack: str, needle: str) -> int:
    # Edge case defined by the problem: empty needle always found at position 0
    if needle == "":
        return 0

    # Needle can't appear in something shorter than itself
    if len(needle) > len(haystack):
        return -1

    # Slide a window of needle's length across haystack
    # Stop early enough that a full match can still fit
    for i in range(len(haystack) - len(needle) + 1):
        if haystack[i:i + len(needle)] == needle:
            return i

    return -1