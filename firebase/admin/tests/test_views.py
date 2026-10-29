"""Reading old view counts from Django's data.json, and the `views` command's arguments.

No database or emulator is needed: the command reads its source before it connects to Firestore.
`copy_views` itself is tested against the emulator in test_store_emulator.py.
"""

import json

import pytest

from wuserade_admin import __main__ as cli
from wuserade_admin import views


def write_dump(tmp_path, records):
    path = tmp_path / "data.json"
    path.write_text(json.dumps(records), encoding="utf-8")
    return path


def poem_record(pk, **fields) -> dict:
    return {"model": "poems.poem", "pk": pk, "fields": fields}


def test_views_from_json_maps_pk_to_views(tmp_path):
    path = tmp_path / "data.json"
    path.write_text('[{"model":"poems.poem","pk":5,"fields":{"views":12}},{"model":"poems.author","pk":1,"fields":{}}]')
    assert views.views_from_json(path) == {5: 12}


def test_views_from_json_reads_every_poem_and_ignores_other_models(tmp_path):
    path = write_dump(
        tmp_path,
        [
            {"model": "poems.theme", "pk": 1, "fields": {"title": "Love", "views": 99}},
            poem_record(3, title="Сурэт", text="Ӏуэхугъуэ\nтекст", views=0),
            {"model": "auth.user", "pk": 3, "fields": {"username": "owner"}},
            poem_record(1, views=7),
            poem_record(2, views=1_500_000),
        ],
    )

    assert views.views_from_json(path) == {3: 0, 1: 7, 2: 1_500_000}


def test_views_from_json_of_a_dump_without_poems_is_empty(tmp_path):
    assert views.views_from_json(write_dump(tmp_path, [])) == {}
    assert views.views_from_json(write_dump(tmp_path, [{"model": "poems.author", "pk": 1, "fields": {}}])) == {}


@pytest.mark.parametrize(
    ("record", "message"),
    [
        (poem_record(5), r"poem 5.*views"),
        (poem_record(5, views=None), r"poem 5.*views"),
        (poem_record(5, views="12"), r"poem 5.*views"),
        (poem_record(5, views=1.5), r"poem 5.*views"),
        (poem_record(5, views=True), r"poem 5.*views"),
        (poem_record(5, views=-1), r"poem 5.*views"),
        ({"model": "poems.poem", "pk": "five", "fields": {"views": 1}}, r"pk"),
        ({"model": "poems.poem", "pk": 5}, r"poem 5.*views"),
    ],
)
def test_views_from_json_names_the_poem_with_a_bad_record(tmp_path, record, message):
    with pytest.raises(ValueError, match=message):
        views.views_from_json(write_dump(tmp_path, [poem_record(1, views=3), record]))


def test_views_from_json_rejects_a_dump_that_is_not_a_list(tmp_path):
    with pytest.raises(ValueError, match="list"):
        views.views_from_json(write_dump(tmp_path, {"poems": []}))


def test_views_from_json_reports_a_missing_or_broken_file(tmp_path):
    with pytest.raises(ValueError, match="nope.json"):
        views.views_from_json(tmp_path / "nope.json")

    broken = tmp_path / "broken.json"
    broken.write_text("[{", encoding="utf-8")
    with pytest.raises(ValueError, match="broken.json.*JSON"):
        views.views_from_json(broken)

    not_utf8 = tmp_path / "latin.json"
    not_utf8.write_bytes(b"[\xff]")
    with pytest.raises(ValueError, match="latin.json.*UTF-8"):
        views.views_from_json(not_utf8)


def test_views_command_needs_exactly_one_of_dsn_or_json(capsys):
    for argv in (["views"], ["views", "--dsn", "postgresql://example/db", "--json", "data.json"]):
        with pytest.raises(SystemExit) as caught:
            cli.main(argv)
        assert caught.value.code == 2
        assert "--dsn" in capsys.readouterr().err


def test_views_command_with_a_missing_dump_reports_an_error_before_connecting(tmp_path, monkeypatch, capsys):
    def no_connection(*args, **kwargs):
        raise AssertionError("connected to Firestore before the dump was read")

    monkeypatch.setattr(cli.store, "connect", no_connection)

    code = cli.main(["views", "--json", str(tmp_path / "nope.json")])

    assert code == 1
    assert "nope.json" in capsys.readouterr().err


def test_views_command_reads_postgres_with_the_masking_read_postgres(monkeypatch, capsys):
    password = "s3cretpw"
    monkeypatch.delenv("DATABASE_URL", raising=False)

    code = cli.main(["views", "--dsn", f"postgresql//user:{password}@host.invalid/db"])

    captured = capsys.readouterr()
    assert code == 1
    assert password not in captured.out + captured.err
    assert "host.invalid" not in captured.out + captured.err
    assert captured.err.startswith("error: could not read Postgres")


def test_views_command_masks_a_url_pasted_without_the_dsn_flag(capsys):
    password = "s3cretpw"

    with pytest.raises(SystemExit):
        cli.main(["views", f"postgresql://user:{password}@db.example/prod", "--json", "data.json"])

    assert password not in capsys.readouterr().err
