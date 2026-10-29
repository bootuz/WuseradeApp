"""Command line for the Wuserade admin tool: python -m wuserade_admin <command>.

Commands:
  migrate    copy themes, authors and poems from the old Postgres into Firestore, rebuild, check counts
  rebuild    recompute counts, the catalog and meta/content after edits made in the Firebase console
  add-poem   add one poem from a text file, then rebuild
  views      copy the old site's view counts onto the poems from Postgres or a data.json dump, then rebuild
  photos     review the photos readers send of poets: list, approve, reject, remove, ban, unban

Credentials: Application Default Credentials. With FIRESTORE_EMULATOR_HOST set, everything
goes to the local emulator (project demo-wuserade) and no credentials are needed. The photos
commands also use Storage and Auth, so they need all three emulators set, or none.
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

from . import photos, store, views  # noqa: E402
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
    print(f"daily re-synced: {result.daily_resynced}")


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


def _views(args: argparse.Namespace) -> int:
    # The source is read before anything connects, so a bad URL or dump stops the command early.
    if args.dsn is not None:
        _, _, poems = read_postgres(args.dsn)
        counts = {poem.id: poem.views for poem in poems}
    else:
        counts = views.views_from_json(args.json)
    db = _connect()
    print(f"views copied: {views.copy_views(db, counts)}")
    try:
        _print_rebuild(store.rebuild(db))
    except ValueError as error:
        raise ValueError(
            f"the view counts were copied, but the rebuild failed: {error}. Fix that, then run 'rebuild'."
        ) from error
    return 0


def _connect_photos() -> photos.PhotoServices:
    services = photos.connect()
    if os.environ.get("FIRESTORE_EMULATOR_HOST"):
        print(f"Using the Firestore, Storage and Auth emulators (project {services.db.project})")
    else:
        print(f"Using Firebase project {services.db.project}")
    return services


def _photos_list(args: argparse.Namespace) -> int:
    waiting = photos.list_submissions(_connect_photos(), args.out)
    for submission in waiting:
        line = f"{submission.id}  {submission.poet_name}  {submission.created_at.astimezone():%Y-%m-%d %H:%M}"
        print(f"{line}  (no photo file)" if submission.path is None else line)
    print(f"{len(waiting)} waiting photos in {args.out}")
    return 0


def _photos_approve(args: argparse.Namespace) -> int:
    url = photos.approve(_connect_photos(), args.submission_id, args.file)
    print(f"approved {args.submission_id}: {url}")
    return 0


def _photos_reject(args: argparse.Namespace) -> int:
    photos.reject(_connect_photos(), args.submission_id)
    print(f"rejected {args.submission_id}")
    return 0


def _photos_remove(args: argparse.Namespace) -> int:
    photos.remove(_connect_photos(), args.author_id)
    print(f"removed the photo of poet {args.author_id}")
    return 0


def _photos_ban(args: argparse.Namespace) -> int:
    uid = photos.sender_uid(args.sender)  # a bad argument is refused before anything connects
    deleted = photos.ban(_connect_photos(), uid)
    print(f"banned {uid}; deleted {deleted} waiting photos")
    return 0


def _photos_unban(args: argparse.Namespace) -> int:
    photos.unban(_connect_photos(), args.uid)
    print(f"unbanned {args.uid}")
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

    views_command = commands.add_parser(
        "views", help="copy the old site's view counts onto the poems, then rebuild"
    )
    views_source = views_command.add_mutually_exclusive_group(required=True)
    views_source.add_argument("--dsn", help="Postgres URL to read the counts from")
    views_source.add_argument(
        "--json",
        type=Path,
        metavar="PATH",
        help="Django data.json dump to read the counts from, for when Postgres is gone",
    )
    views_command.set_defaults(handler=_views)

    photo_commands = commands.add_parser(
        "photos", help="review the photos readers send of poets"
    ).add_subparsers(dest="photos_command", required=True)

    photos_list = photo_commands.add_parser("list", help="download the waiting photos and list them")
    photos_list.add_argument(
        "--out",
        type=Path,
        default=Path.home() / "Downloads" / "wuserade-photos",
        help="folder for the downloaded photos (default: ~/Downloads/wuserade-photos)",
    )
    photos_list.set_defaults(handler=_photos_list)

    approve = photo_commands.add_parser("approve", help="publish a waiting photo as the poet's photo")
    approve.add_argument("submission_id", metavar="SUBMISSION_ID", help="as printed by 'photos list', like 12_uid")
    approve.add_argument("--file", type=Path, help="publish this edited copy instead of the submitted file")
    approve.set_defaults(handler=_photos_approve)

    reject = photo_commands.add_parser("reject", help="delete a waiting photo")
    reject.add_argument("submission_id", metavar="SUBMISSION_ID")
    reject.set_defaults(handler=_photos_reject)

    remove = photo_commands.add_parser("remove", help="take a poet's published photo down")
    remove.add_argument("author_id", metavar="AUTHOR_ID", type=int)
    remove.set_defaults(handler=_photos_remove)

    ban = photo_commands.add_parser("ban", help="stop a sender from sending photos and delete their waiting ones")
    ban.add_argument("sender", metavar="UID_OR_SUBMISSION_ID", help="a uid, or a submission id like 12_uid")
    ban.set_defaults(handler=_photos_ban)

    unban = photo_commands.add_parser("unban", help="let a blocked sender send photos again")
    unban.add_argument("uid", metavar="UID")
    unban.set_defaults(handler=_photos_unban)
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
