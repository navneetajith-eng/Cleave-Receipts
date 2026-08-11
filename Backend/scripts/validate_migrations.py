from __future__ import annotations

import re
from pathlib import Path


MIGRATION_NAME = re.compile(r"^(\d{3})_[a-z0-9_]+\.sql$")
UNSAFE_PATTERNS = {
    r"using\s*\(\s*true\s*\)": "open RLS USING (true) policy",
    r"with\s+check\s*\(\s*true\s*\)": "open RLS WITH CHECK (true) policy",
    r"disable\s+row\s+level\s+security": "RLS disable statement",
}


def main() -> None:
    migration_dir = Path(__file__).resolve().parents[1] / "migrations"
    migrations = sorted(migration_dir.glob("*.sql"))
    if not migrations:
        raise SystemExit("No SQL migrations found")

    numbers: list[int] = []
    errors: list[str] = []
    for migration in migrations:
        match = MIGRATION_NAME.fullmatch(migration.name)
        if match is None:
            errors.append(f"Invalid migration filename: {migration.name}")
            continue
        numbers.append(int(match.group(1)))
        sql = migration.read_text(encoding="utf-8")
        sql_without_line_comments = re.sub(r"--[^\n]*", "", sql)
        if not sql_without_line_comments.strip().endswith(";"):
            errors.append(f"Migration must end with a semicolon: {migration.name}")
        for pattern, description in UNSAFE_PATTERNS.items():
            if re.search(pattern, sql, flags=re.IGNORECASE):
                errors.append(f"{migration.name}: {description}")

    expected = list(range(1, len(numbers) + 1))
    if numbers != expected:
        errors.append(f"Migration sequence must be contiguous; found {numbers}, expected {expected}")
    if errors:
        raise SystemExit("\n".join(errors))

    print(f"Validated {len(migrations)} migrations")


if __name__ == "__main__":
    main()
