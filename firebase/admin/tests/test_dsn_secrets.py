"""The database URL carries the Postgres password; no error path may print it. No DB or emulator needed."""

import traceback

import psycopg
import pytest

from wuserade_admin import __main__ as cli
from wuserade_admin import source

PASSWORD = "s3cretpw"

# psycopg/libpq quote (part of) the URL when they cannot parse it. None of these touch the network.
MALFORMED = [
    f"postgresql//user:{PASSWORD}@host.invalid/db",
    f"postgresql://user:{PASSWORD}@host.invalid/db?sslmode",
    f"postgresql://user:{PASSWORD}@[::1/db",
    f"host=host.invalid user=user password={PASSWORD} bogus",
    f"host=host.invalid password='{PASSWORD}' nosuchoption=1",
]


def everything_printable(error: BaseException) -> str:
    return str(error) + repr(error) + "".join(traceback.format_exception(error))


@pytest.mark.parametrize("dsn", MALFORMED)
def test_malformed_url_error_never_contains_the_password(dsn):
    with pytest.raises(ValueError) as caught:
        source.read_postgres(dsn)

    error = caught.value
    assert PASSWORD not in everything_printable(error)
    assert dsn not in everything_printable(error)
    # The original exception quotes the URL, so it must not stay attached for a traceback to print.
    assert error.__cause__ is None
    assert error.__suppress_context__
    assert "not valid" in str(error)
    # The fixed hint must survive the CLI's output masking unchanged.
    assert source.mask_passwords(str(error)) == str(error)


def test_connection_errors_that_quote_the_url_are_redacted(monkeypatch):
    dsn = f"postgresql://user:{PASSWORD}@db.example/prod"

    def failing_connect(conninfo, **kwargs):
        raise psycopg.OperationalError(
            f'connection failed for "{conninfo}"; password {PASSWORD}; user:{PASSWORD}@db.example'
        )

    monkeypatch.setattr(source.psycopg, "connect", failing_connect)

    with pytest.raises(ValueError) as caught:
        source.read_postgres(dsn)

    message = str(caught.value)
    assert message.startswith("could not read Postgres: ")
    assert PASSWORD not in everything_printable(caught.value)
    assert dsn not in everything_printable(caught.value)
    assert "db.example" in message  # the host is not secret and helps the owner


def test_percent_encoded_passwords_are_redacted_in_both_forms(monkeypatch):
    dsn = "postgresql://user:p%40ss%2Fword@db.example/prod"

    def failing_connect(conninfo, **kwargs):
        raise psycopg.OperationalError("login failed with p@ss/word (p%40ss%2Fword)")

    monkeypatch.setattr(source.psycopg, "connect", failing_connect)

    with pytest.raises(ValueError) as caught:
        source.read_postgres(dsn)

    assert "p@ss/word" not in str(caught.value)
    assert "p%40ss%2Fword" not in str(caught.value)
    assert "ss/word" not in str(caught.value)


def test_unexpected_errors_are_withheld(monkeypatch):
    dsn = f"postgresql://user:{PASSWORD}@db.example/prod"

    def failing_connect(conninfo, **kwargs):
        raise RuntimeError(f"surprise: {conninfo}")

    monkeypatch.setattr(source.psycopg, "connect", failing_connect)

    with pytest.raises(ValueError) as caught:
        source.read_postgres(dsn)

    assert "RuntimeError" in str(caught.value)
    assert PASSWORD not in everything_printable(caught.value)
    assert caught.value.__cause__ is None
    assert caught.value.__suppress_context__


def test_server_side_errors_keep_their_message(monkeypatch):
    # A missing table has a SQLSTATE and never quotes the URL, so the owner gets the real reason.
    def failing_connect(conninfo, **kwargs):
        raise psycopg.errors.UndefinedTable('relation "poems_theme" does not exist')

    monkeypatch.setattr(source.psycopg, "connect", failing_connect)

    with pytest.raises(ValueError, match="poems_theme"):
        source.read_postgres(f"postgresql://user:{PASSWORD}@db.example/prod")


@pytest.mark.parametrize(
    "text",
    [
        f"unrecognized arguments: postgresql://user:{PASSWORD}@db.example/prod",
        f"bad value postgresql//user:{PASSWORD}@db.example/prod",
        f"user:{PASSWORD}@db.example",
        f"host=db.example password={PASSWORD} dbname=prod",
        f"host=db.example password='{PASSWORD}' dbname=prod",
        f"PASSWORD = {PASSWORD}",
        "user:p@ss@db.example",
    ],
)
def test_mask_passwords_hides_url_and_keyword_forms(text):
    masked = source.mask_passwords(text)

    assert PASSWORD not in masked
    assert "p@ss" not in masked and "ss@db" not in masked
    assert "<password>" in masked


def test_mask_passwords_leaves_ordinary_messages_alone():
    for text in (
        "poems/3 references author 999, which does not exist",
        "password authentication failed for user",
        "author 55 does not exist",
        "title must not be empty",
    ):
        assert source.mask_passwords(text) == text


def test_cli_migrate_with_a_malformed_url_prints_no_password(capsys, monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)

    code = cli.main(["migrate", "--dsn", f"postgresql//user:{PASSWORD}@host.invalid/db"])

    captured = capsys.readouterr()
    assert code == 1
    assert PASSWORD not in captured.out + captured.err
    assert "host.invalid" not in captured.out + captured.err
    assert captured.err.startswith("error: could not read Postgres")


def test_cli_migrate_with_the_url_pasted_without_dsn_flag_prints_no_password(capsys):
    # argparse reports unrecognized arguments verbatim.
    with pytest.raises(SystemExit) as caught:
        cli.main(["migrate", f"postgresql://user:{PASSWORD}@db.example/prod"])

    captured = capsys.readouterr()
    assert caught.value.code == 2
    assert "unrecognized arguments" in captured.err
    assert PASSWORD not in captured.out + captured.err


def test_cli_masks_a_password_in_any_error_it_prints(capsys, monkeypatch):
    def leaky(args):
        raise ValueError(f"something quoted user:{PASSWORD}@db.example/prod")

    monkeypatch.setattr(cli, "_rebuild", leaky)

    code = cli.main(["rebuild"])

    assert code == 1
    assert PASSWORD not in capsys.readouterr().err
