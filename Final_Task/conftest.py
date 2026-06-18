import os
import pytest


@pytest.fixture(autouse=True)
def change_to_final_task_dir(monkeypatch):
    monkeypatch.chdir(os.path.dirname(os.path.abspath(__file__)))
