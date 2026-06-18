PASSING_GRADE = 8


class Trainee:
    def __init__(self, name, surname):
        self.name = name
        self.surname = surname

        # Tracking counters — these accumulate raw event counts
        self.visited_lectures = 0    # +1 per visit
        self.done_home_tasks = 0     # +2 per homework done
        self.missed_lectures = 0     # -1 per missed lecture
        self.missed_home_tasks = 0   # -2 per missed homework

        # The actual grade — clamped between 0 and 10 at all times
        self.mark = 0

    def visit_lecture(self):
        self.visited_lectures += 1
        # Attending a lecture is worth 1 point
        self._add_points(1)

    def do_homework(self):
        self.done_home_tasks += 2
        # Completing homework is worth 2 points
        self._add_points(2)

    def miss_lecture(self):
        self.missed_lectures -= 1
        # Missing a lecture costs 1 point
        self._subtract_points(1)

    def miss_homework(self):
        self.missed_home_tasks -= 2
        # Missing homework costs 2 points
        self._subtract_points(2)

    def _add_points(self, points: int):
        # The mark can never exceed 10 — cap it
        self.mark = min(10, self.mark + points)

    def _subtract_points(self, points: int):
        # The mark can never go below 0 — floor it
        self.mark = max(0, self.mark - points)

    def is_passed(self):
        if self.mark >= PASSING_GRADE:
            print("Good job!")
        else:
            missing = PASSING_GRADE - self.mark
            print(f"You need to get {missing} more points. Try to do your best!")

    def __str__(self):
        status = (
            f"Trainee {self.name.title()} {self.surname.title()}:\n"
            f"done homework {self.done_home_tasks} points;\n"
            f"missed homework {self.missed_home_tasks} points;\n"
            f"visited lectures {self.visited_lectures} points;\n"
            f"missed lectures {self.missed_lectures} points;\n"
            f"current mark {self.mark};\n"
        )
        return status