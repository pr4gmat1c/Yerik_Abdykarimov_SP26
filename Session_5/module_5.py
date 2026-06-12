import os
import re
from collections import Counter
from pathlib import Path
from random import choice, seed
from typing import List, Union

import requests
from requests.exceptions import RequestException


S5_PATH = Path(os.path.realpath(__file__)).parent

PATH_TO_NAMES = S5_PATH / "names.txt"
PATH_TO_SURNAMES = S5_PATH / "last_names.txt"
PATH_TO_OUTPUT = S5_PATH / "sorted_names_and_surnames.txt"
PATH_TO_TEXT = S5_PATH / "random_text.txt"
PATH_TO_STOP_WORDS = S5_PATH / "stop_words.txt"


def task_1():
    seed(1)
    with open(PATH_TO_NAMES, encoding="utf-8") as f:
        names = sorted(line.strip().lower() for line in f if line.strip())
    with open(PATH_TO_SURNAMES, encoding="utf-8") as f:
        surnames = [line.strip().lower() for line in f if line.strip()]

    with open(PATH_TO_OUTPUT, "w", encoding="utf-8") as f:
        for name in names:
            f.write(f"{name} {choice(surnames)}\n")


def task_2(top_k: int):
    with open(PATH_TO_TEXT, encoding="utf-8") as f:
        text = f.read()
    with open(PATH_TO_STOP_WORDS, encoding="utf-8") as f:
        stop_words = {line.strip().lower() for line in f if line.strip()}

    words = [w for w in re.findall(r'[a-z]+', text.lower()) if w not in stop_words]
    return Counter(words).most_common(top_k)


def task_3(url: str):
    try:
        response = requests.get(url)
        response.raise_for_status()
        return response
    except requests.exceptions.RequestException:
        raise RequestException()


def task_4(data: List[Union[int, str, float]]):
    total = 0
    for item in data:
        try:
            total += item
        except TypeError:
            total += float(item)
    return total


def task_5():
    a, b = input().split()
    try:
        print(float(a) / float(b))
    except ZeroDivisionError:
        print("Can't divide by zero")
    except ValueError:
        print("Entered value is wrong")
