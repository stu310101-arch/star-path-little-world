"""Publish one generated sibling file without deleting the old file first."""
import os
from pathlib import Path
import sys
import time


def publish(staged: Path, target: Path, directory: Path) -> None:
    staged = staged.resolve()
    target = target.resolve()
    directory = directory.resolve()
    if staged.parent != directory or target.parent != directory:
        raise ValueError("Generated publication paths must stay in the output directory")
    if not staged.name.startswith(".building_") or staged == target:
        raise ValueError("Expected a distinct staged generated file")
    for attempt in range(10):
        try:
            # MoveFileExW(REPLACE_EXISTING) on Windows; rename(2) on POSIX.
            # Unlike Godot 4.7.2 DirAccessWindows.rename, this never unlinks
            # the old destination before attempting the replacement.
            os.replace(staged, target)
            return
        except OSError:
            if attempt == 9:
                raise
            time.sleep(0.1 * (attempt + 1))


if __name__ == "__main__":
    try:
        publish(*(Path(value) for value in sys.argv[1:4]))
    except (OSError, ValueError, TypeError) as error:
        print(f"Generated publication failed; staged file preserved: {error}", file=sys.stderr)
        sys.exit(1)
