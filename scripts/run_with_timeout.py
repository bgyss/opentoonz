#!/usr/bin/env python3
import argparse
import subprocess
import sys


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("seconds", type=float)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv[1:])

    if args.seconds <= 0:
        print("run-with-timeout: timeout must be positive", file=sys.stderr)
        return 2
    if not args.command:
        print("run-with-timeout: missing command", file=sys.stderr)
        return 2

    try:
        completed = subprocess.run(args.command, timeout=args.seconds)
        return completed.returncode
    except subprocess.TimeoutExpired:
        print(
            f"run-with-timeout: command timed out after {args.seconds:g}s",
            file=sys.stderr,
        )
        return 124


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
