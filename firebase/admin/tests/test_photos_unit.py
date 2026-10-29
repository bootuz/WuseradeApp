"""Pure tests for wuserade_admin.photos: image processing, URLs and ids. No emulator needed."""

from io import BytesIO

import pytest
from PIL import Image, ImageCms

from wuserade_admin import photos

ORIENTATION = 0x0112
GPS_IFD = 0x8825
EMULATOR_VARIABLES = [
    "FIRESTORE_EMULATOR_HOST",
    "STORAGE_EMULATOR_HOST",
    "FIREBASE_STORAGE_EMULATOR_HOST",
    "FIREBASE_AUTH_EMULATOR_HOST",
]


def jpeg_bytes(width: int, height: int, orientation: int = 1, gps: bool = False, **save_options) -> bytes:
    """A JPEG with an EXIF orientation tag and, with `gps`, a GPS block holding a latitude.

    `save_options` go to Pillow's save, for example `comment=`, `xmp=` or `icc_profile=`.
    """
    exif = Image.Exif()
    exif[ORIENTATION] = orientation
    if gps:
        exif[GPS_IFD] = {1: "N", 2: (41.0, 12.0, 0.0)}
    buffer = BytesIO()
    Image.new("RGB", (width, height), (200, 30, 30)).save(buffer, "JPEG", exif=exif, **save_options)
    return buffer.getvalue()


def png_bytes(image: Image.Image, **save_options) -> bytes:
    buffer = BytesIO()
    image.save(buffer, "PNG", **save_options)
    return buffer.getvalue()


def clear_emulator_variables(monkeypatch) -> None:
    for name in EMULATOR_VARIABLES:
        monkeypatch.delenv(name, raising=False)


@pytest.fixture
def no_clients(monkeypatch):
    """No emulator variables, and building any client or app fails the test."""
    clear_emulator_variables(monkeypatch)

    def built(*args, **kwargs):
        raise AssertionError("a client was built")

    monkeypatch.setattr(photos.store, "connect", built)
    monkeypatch.setattr(photos.storage, "Client", built)
    monkeypatch.setattr(photos.firebase_admin, "initialize_app", built)
    monkeypatch.setattr(photos.firebase_storage, "bucket", built)


def test_publishable_jpeg_shrinks_the_long_side_to_1024():
    out = Image.open(BytesIO(photos.publishable_jpeg(jpeg_bytes(3000, 2000))))
    assert out.format == "JPEG" and out.size == (1024, 683)


def test_publishable_jpeg_keeps_small_photos_their_size():
    assert Image.open(BytesIO(photos.publishable_jpeg(jpeg_bytes(500, 400)))).size == (500, 400)


def test_publishable_jpeg_applies_orientation_and_drops_exif():
    source = jpeg_bytes(300, 100, orientation=6, gps=True)
    assert Image.open(BytesIO(source)).getexif().get_ifd(GPS_IFD), "the test photo must carry a location"

    out = Image.open(BytesIO(photos.publishable_jpeg(source)))

    assert out.size == (100, 300)
    assert len(out.getexif()) == 0


def test_publishable_jpeg_carries_no_comment_or_other_metadata():
    source = jpeg_bytes(
        300, 200, orientation=6, gps=True,
        comment=b"lat=41.2N lon=43.1E secret", xmp=b"<x:xmpmeta>xmp-secret</x:xmpmeta>",
    )
    carried = Image.open(BytesIO(source))
    assert carried.info["comment"] and carried.info["xmp"], "the test photo must carry both"

    output = photos.publishable_jpeg(source)

    out = Image.open(BytesIO(output))
    assert "comment" not in out.info and "xmp" not in out.info
    assert len(out.getexif()) == 0
    assert b"secret" not in output


def test_publishable_jpeg_keeps_an_rgb_colour_profile():
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    source = jpeg_bytes(300, 200, icc_profile=profile)
    assert Image.open(BytesIO(source)).info["icc_profile"] == profile

    out = Image.open(BytesIO(photos.publishable_jpeg(source)))

    assert out.info["icc_profile"] == profile


def test_publishable_jpeg_drops_a_colour_profile_that_is_not_rgb():
    buffer = BytesIO()
    Image.new("CMYK", (40, 30)).save(buffer, "JPEG", icc_profile=b"a CMYK profile")

    out = Image.open(BytesIO(photos.publishable_jpeg(buffer.getvalue())))

    assert out.mode == "RGB" and "icc_profile" not in out.info


def is_white(pixel: tuple[int, ...]) -> bool:
    return all(channel >= 250 for channel in pixel)  # JPEG may be a few steps off


def test_publishable_jpeg_flattens_a_png_with_alpha_onto_white():
    source = Image.new("RGBA", (40, 30), (10, 20, 30, 0))  # fully transparent, a dark colour stored under it
    source.paste((200, 30, 30, 255), (0, 0, 20, 30))  # the left half is opaque red

    out = Image.open(BytesIO(photos.publishable_jpeg(png_bytes(source))))

    assert out.format == "JPEG" and out.mode == "RGB" and out.size == (40, 30)
    assert is_white(out.getpixel((35, 15)))
    red, green, blue = out.getpixel((5, 15))
    assert red > 180 and green < 60 and blue < 60


def test_publishable_jpeg_flattens_a_palette_png_with_a_transparent_colour_onto_white():
    source = Image.new("P", (40, 30), 0)
    source.putpalette([10, 20, 30] + [0] * 765)

    out = Image.open(BytesIO(photos.publishable_jpeg(png_bytes(source, transparency=0))))

    assert out.mode == "RGB" and is_white(out.getpixel((20, 15)))


def test_publishable_jpeg_rejects_data_that_is_not_an_image():
    with pytest.raises(ValueError, match="not an image"):
        photos.publishable_jpeg(b"definitely not an image")


def test_download_url():
    assert photos.download_url(photos.PUBLIC_HOST, photos.BUCKET, "poets/12.jpg", "tok") == (
        "https://firebasestorage.googleapis.com/v0/b/wuserade.firebasestorage.app/o/poets%2F12.jpg?alt=media&token=tok"
    )


def test_submission_path():
    assert photos.submission_path(12, "uid") == "photo-submissions/12/uid.jpg"


def test_poet_path():
    assert photos.poet_path(12) == "poets/12.jpg"


def test_parse_submission_id():
    assert photos.parse_submission_id("12_abc") == (12, "abc")
    for bad in ["", "12", "x_abc", "12_", "_abc", "12_a_b"]:
        with pytest.raises(ValueError):
            photos.parse_submission_id(bad)


def test_sender_uid_takes_a_uid_or_a_submission_id():
    assert photos.sender_uid("alice") == "alice"
    assert photos.sender_uid("12_alice") == "alice"
    for bad in ["", "  ", "12_a_b", "_alice", "x_alice"]:
        with pytest.raises(ValueError):
            photos.sender_uid(bad)


def test_connect_refuses_a_partial_emulator_setup(monkeypatch):
    monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8080")
    monkeypatch.delenv("STORAGE_EMULATOR_HOST", raising=False)
    monkeypatch.delenv("FIREBASE_STORAGE_EMULATOR_HOST", raising=False)
    with pytest.raises(ValueError, match="firestore,storage,auth"):
        photos.connect()


@pytest.mark.parametrize(
    "set_variables",
    [
        ("FIRESTORE_EMULATOR_HOST",),
        ("STORAGE_EMULATOR_HOST",),
        ("FIREBASE_STORAGE_EMULATOR_HOST",),
        ("FIREBASE_AUTH_EMULATOR_HOST",),
        ("FIRESTORE_EMULATOR_HOST", "STORAGE_EMULATOR_HOST"),
        ("FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"),
        ("STORAGE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"),
        ("FIREBASE_STORAGE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"),
    ],
    ids="+".join,
)
def test_connect_refuses_some_emulators_without_the_others(no_clients, monkeypatch, set_variables):
    for name in set_variables:
        monkeypatch.setenv(name, "127.0.0.1:1")

    with pytest.raises(ValueError, match="firestore,storage,auth"):
        photos.connect()


def test_connect_with_no_emulator_variables_uses_project_wuserade(monkeypatch):
    clear_emulator_variables(monkeypatch)
    monkeypatch.setattr(photos.store, "connect", lambda: "the real database")
    monkeypatch.setattr(photos.firebase_storage, "bucket", lambda name: f"bucket {name}")

    services = photos.connect()

    assert services.db == "the real database"
    assert services.bucket == "bucket wuserade.firebasestorage.app"
    assert services.download_host == photos.PUBLIC_HOST


def test_storage_emulator_host_adds_the_scheme_the_firebase_variable_lacks(monkeypatch):
    monkeypatch.delenv("STORAGE_EMULATOR_HOST", raising=False)
    monkeypatch.setenv("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9199")
    assert photos.storage_emulator_host() == "http://127.0.0.1:9199"

    monkeypatch.setenv("STORAGE_EMULATOR_HOST", "http://localhost:9000")
    assert photos.storage_emulator_host() == "http://localhost:9000"

    monkeypatch.delenv("STORAGE_EMULATOR_HOST")
    monkeypatch.delenv("FIREBASE_STORAGE_EMULATOR_HOST")
    assert photos.storage_emulator_host() is None
