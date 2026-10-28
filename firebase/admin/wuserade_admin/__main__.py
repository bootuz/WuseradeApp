"""Command line for the Wuserade admin tool: python -m wuserade_admin <command>.

Commands:
  migrate    copy themes, authors and poems from the old Postgres into Firestore, rebuild, check counts
  rebuild    recompute counts, the catalog and meta/content after edits made in the Firebase console
  add-poem   add one poem from a text file, then rebuild

Credentials: Application Default Credentials. With FIRESTORE_EMULATOR_HOST set, everything
goes to the local emulator (project demo-wuserade) and no credentials are needed.
"""

from __future__ import annotations

import argparse
import os
import sys
import warnings
from pathlib import Path

# Google libraries warn that Python 3.11 loses support in 2027. Not actionable yet, and it would
# print on every run. Must be set before the Google imports below.
warnings.filterwarnings("ignore", message="You are using a Python version", category=FutureWarning)

from dotenv import load_dotenv  # noqa: E402

from . import store  # noqa: E402
from .source import mask_passwords, read_postgres  # noqa: E402

ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


def _connect():
    db = store.connect()
    if os.environ.get("FIRESTORE_EMULATOR_HOST"):
        print(f"Using the Firestore emulator at {os.environ['FIRESTORE_EMULATOR_HOST']} (project {db.project})")
    else:
        print(f"Using Firestore project {db.project}")
    return db


def _print_rebuild(result: store.RebuildResult) -> None:
    print(
        f"Catalog version {result.catalog_version}: {result.chunks} chunk(s), {result.poems} poems, "
        f"{result.authors_with_poems} authors with poems, {result.themes} themes."
    )


def _format_counts(counts: dict[str, int]) -> str:
    return " ".join(f"{name}={counts[name]}" for name in ("themes", "authors", "poems"))


def _migrate(args: argparse.Namespace) -> int:
    dsn = args.dsn or os.environ.get("DATABASE_URL")
    if not dsn:
        print(
            "error: no database URL. Pass --dsn, or set DATABASE_URL in the environment "
            "or in firebase/admin/.env",
            file=sys.stderr,
        )
        return 2
    themes, authors, poems = read_postgres(dsn)
    db = _connect()
    store.upsert_content(db, themes, authors, poems)
    _print_rebuild(store.rebuild(db))

    postgres = {"themes": len(themes), "authors": len(authors), "poems": len(poems)}
    firestore_counts = store.count_documents(db)
    print(f"Postgres:  {_format_counts(postgres)}")
    print(f"Firestore: {_format_counts(firestore_counts)}")
    differing = [name for name in postgres if postgres[name] != firestore_counts[name]]
    if differing:
        for name in differing:
            print(
                f"MISMATCH in {name}: Postgres {postgres[name]}, Firestore {firestore_counts[name]}",
                file=sys.stderr,
            )
        return 1
    print("Counts match.")
    return 0


def _rebuild(args: argparse.Namespace) -> int:
    _print_rebuild(store.rebuild(_connect(), minimum_app_version=args.min_version))
    return 0


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError as error:
        raise ValueError(f"cannot read {path}: {error.strerror}") from error
    except UnicodeDecodeError:
        raise ValueError(f"{path} is not valid UTF-8") from None


def _add_poem(args: argparse.Namespace) -> int:
    text = _read_text(args.text_file)
    db = _connect()
    poem_id = store.add_poem(db, args.title, text, args.author_id, args.theme_id)
    print(f"Added poem {poem_id}.")
    try:
        _print_rebuild(store.rebuild(db))
    except ValueError as error:
        raise ValueError(
            f"poem {poem_id} was added, but the rebuild failed: {error}. Fix that, then run 'rebuild'."
        ) from error
    return 0


class _Parser(argparse.ArgumentParser):
    """argparse echoes unrecognized arguments; a database URL pasted without --dsn must not leak."""

    def error(self, message: str):
        super().error(mask_passwords(message))


def build_parser() -> argparse.ArgumentParser:
    parser = _Parser(prog="python -m wuserade_admin", description=__doc__.split("\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)

    migrate = commands.add_parser("migrate", help="copy content from Postgres into Firestore and rebuild")
    migrate.add_argument("--dsn", help="Postgres URL (default: DATABASE_URL from the environment or .env)")
    migrate.set_defaults(handler=_migrate)

    rebuild = commands.add_parser("rebuild", help="recompute counts, catalog and meta/content")
    rebuild.add_argument(
        "--min-version",
        help="set meta/content.minimumAppVersion; omit to keep the current value, pass '' to clear it",
    )
    rebuild.set_defaults(handler=_rebuild)

    add_poem = commands.add_parser("add-poem", help="add a poem from a text file, then rebuild")
    add_poem.add_argument("--title", required=True)
    add_poem.add_argument("--text-file", required=True, type=Path, help="UTF-8 file with the poem text")
    add_poem.add_argument("--author-id", required=True, type=int)
    add_poem.add_argument("--theme-id", type=int)
    add_poem.set_defaults(handler=_add_poem)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.handler(args)
    except ValueError as error:
        print(f"error: {mask_passwords(str(error))}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    # Only the real entry point reads firebase/admin/.env (git-ignored); tests call main() directly.
    load_dotenv(ENV_FILE)
    sys.exit(main())
