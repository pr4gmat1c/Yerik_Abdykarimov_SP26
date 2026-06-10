import time
from typing import List

Matrix = List[List[int]]


def task_1(exp: int):
    # The outer function captures 'exp' in its enclosing scope —
    # that's the closure. Every call to task_1 bakes a different
    # exponent into the returned function.
    def power(base):
        return base ** exp

    return power


def task_2(*args, **kwargs):
    # *args catches all positional arguments as a tuple
    # **kwargs catches all keyword arguments as a dict
    # We print positional ones first, then keyword values in insertion order
    for arg in args:
        print(arg)
    for value in kwargs.values():
        print(value)


def helper(func):
    # A decorator wraps the original function with extra behaviour
    # before and/or after the call. We use *args/**kwargs so it works
    # on any function signature without modification.
    def wrapper(*args, **kwargs):
        print("Hi, friend! What's your name?")
        func(*args, **kwargs)          # the actual function runs here
        print("See you soon!")
    return wrapper


@helper
def task_3(name: str):
    print(f"Hello! My name is {name}.")


def timer(func):
    # Captures the start time, runs the function, then compares with
    # the end time. The exact format string is required by the tests.
    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        run_time = time.time() - start
        print(f"Finished {func.__name__} in {run_time:.4f} secs")
        return result
    return wrapper


@timer
def task_4():
    return len([1 for _ in range(0, 10**8)])


def task_5(matrix: Matrix) -> Matrix:
    # zip(*matrix) unpacks the rows and re-zips by column position,
    # effectively flipping rows and columns — that's the transpose.
    # list() converts each zip tuple back into a proper list.
    return [list(row) for row in zip(*matrix)]


def task_6(queue: str):
    # Classic stack approach: push on '(', pop on ')'.
    # If we ever try to pop from an empty stack, a ')' arrived too early → False.
    # At the end, the stack must be empty — every '(' was matched.
    stack = []
    for char in queue:
        if char == "(":
            stack.append(char)
        elif char == ")":
            if not stack:
                return False
            stack.pop()
    return len(stack) == 0
