"""
test_registers.py -- schema + ground-truth validation for registers.json.

Run from the forth_dashboard_v2 directory::

    python3 -m pytest tests/test_registers.py

The test loads the checked-in ``data/registers.json`` and independently loads
the v1 source dicts (``peripherals_config`` / ``bitfields_config``) to
cross-check that the generator faithfully reproduced them. It also proves the
generator is deterministic (regenerating into a temp file is byte-identical).
"""

import json
import os
import subprocess
import sys
import tempfile

import pytest

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
_TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.abspath(os.path.join(_TESTS_DIR, ".."))          # forth_dashboard_v2/
DATA_DIR = os.path.join(_ROOT, "data")
JSON_PATH = os.path.join(DATA_DIR, "registers.json")
GEN_PATH = os.path.join(DATA_DIR, "gen_registers.py")
V1_DIR = os.path.abspath(os.path.join(_ROOT, "..", "forth_dashboard"))


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
@pytest.fixture(scope="module")
def doc():
    """Parse the checked-in registers.json."""
    with open(JSON_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)


@pytest.fixture(scope="module")
def v1():
    """Independently load the v1 source dicts (single source of truth)."""
    if V1_DIR not in sys.path:
        sys.path.insert(0, V1_DIR)
    import peripherals_config
    import bitfields_config

    return peripherals_config.PERIPHERALS, bitfields_config.BITFIELDS


# ---------------------------------------------------------------------------
# Structural / schema checks
# ---------------------------------------------------------------------------
def test_json_parses_and_top_level_shape(doc):
    assert isinstance(doc, dict)
    assert doc["chip"] == "myshkin"
    assert isinstance(doc["generated_from"], str) and doc["generated_from"]
    assert isinstance(doc["peripherals"], dict)
    assert doc["peripherals"], "peripherals must not be empty"


def test_peripheral_and_register_schema(doc):
    for pname, pdef in doc["peripherals"].items():
        assert isinstance(pname, str) and pname
        assert isinstance(pdef["description"], str)
        assert isinstance(pdef["base_addr"], int)
        assert isinstance(pdef["registers"], dict) and pdef["registers"]
        for rname, rdef in pdef["registers"].items():
            assert isinstance(rname, str) and rname
            assert isinstance(rdef["addr"], int)
            assert isinstance(rdef["size"], int) and rdef["size"] > 0
            assert isinstance(rdef["type"], str) and rdef["type"]
            assert isinstance(rdef["description"], str)
            assert isinstance(rdef["fields"], dict)  # {} allowed
            for fname, fdef in rdef["fields"].items():
                assert isinstance(fname, str) and fname
                assert isinstance(fdef["lsb"], int) and fdef["lsb"] >= 0
                assert isinstance(fdef["width"], int) and fdef["width"] >= 1
                assert isinstance(fdef["desc"], str)
                vals = fdef["values"]
                assert vals is None or isinstance(vals, dict)
                if isinstance(vals, dict):
                    for k, v in vals.items():
                        # enum keys are stringified integers
                        assert isinstance(k, str) and k.lstrip("-").isdigit()
                        assert isinstance(v, str)


def test_keys_are_sorted(doc):
    """Peripheral, register, and field keys are emitted in sorted order."""
    periphs = list(doc["peripherals"].keys())
    assert periphs == sorted(periphs)
    for pdef in doc["peripherals"].values():
        regs = list(pdef["registers"].keys())
        assert regs == sorted(regs)
        for rdef in pdef["registers"].values():
            fields = list(rdef["fields"].keys())
            assert fields == sorted(fields)


# ---------------------------------------------------------------------------
# Ground-truth spot checks (hard-coded)
# ---------------------------------------------------------------------------
def test_spot_checks(doc):
    p = doc["peripherals"]
    assert p["GPIO0"]["registers"]["PIN"]["addr"] == 0x4000
    assert p["SYSTEM"]["base_addr"] == 0x4900
    assert p["I2C1"]["base_addr"] == 0x4F00

    br = p["SPI0"]["registers"]["CR"]["fields"]["BR"]
    assert br["lsb"] == 8
    assert br["width"] == 8
    assert br["values"] is None  # numeric field

    # SPI1 shares the same 'SPI_CR' bitfield block as SPI0.
    assert p["SPI1"]["registers"]["CR"]["fields"]["BR"]["lsb"] == 8

    # Ranged field low-element-is-LSB, general case (SARADC_CR.SAMPLESTEP [1,4]).
    ss = p["SARADC"]["registers"]["CR"]["fields"]["SAMPLESTEP"]
    assert ss["lsb"] == 1 and ss["width"] == 4

    # Scalar-LSB-with-width>1 field (POTENTIOSTAT TPR DTP1 is width 5 at LSB 5).
    dtp1 = p["POTENTIOSTAT"]["registers"]["TPR"]["fields"]["DTP1"]
    assert dtp1["lsb"] == 5 and dtp1["width"] == 5


# ---------------------------------------------------------------------------
# Invariants
# ---------------------------------------------------------------------------
def test_fields_fit_in_register(doc):
    """Every resolved field fits inside its register (lsb+width <= 8*size).

    Verified to hold for all 369 resolved fields in the v1 data; if a v1 quirk
    ever breaks it, this test surfaces the offender explicitly.
    """
    offenders = []
    for pname, pdef in doc["peripherals"].items():
        for rname, rdef in pdef["registers"].items():
            reg_bits = 8 * rdef["size"]
            for fname, fdef in rdef["fields"].items():
                if fdef["lsb"] + fdef["width"] > reg_bits:
                    offenders.append(
                        "%s.%s.%s lsb=%d width=%d size=%d"
                        % (pname, rname, fname, fdef["lsb"], fdef["width"], rdef["size"])
                    )
    assert not offenders, "fields exceed register width: " + "; ".join(offenders)


def test_no_duplicate_addresses_within_peripheral(doc):
    for pname, pdef in doc["peripherals"].items():
        addrs = [rdef["addr"] for rdef in pdef["registers"].values()]
        assert len(addrs) == len(set(addrs)), "duplicate register address in %s" % pname


def test_addr_within_page_of_base(doc):
    """Every register address lives within the peripheral's 256-byte page."""
    for pname, pdef in doc["peripherals"].items():
        base = pdef["base_addr"]
        for rname, rdef in pdef["registers"].items():
            assert base <= rdef["addr"] < base + 0x100, "%s.%s" % (pname, rname)


# ---------------------------------------------------------------------------
# Cross-check vs the v1 dicts (loaded independently)
# ---------------------------------------------------------------------------
def test_matches_v1_peripherals_and_registers(doc, v1):
    peripherals, _ = v1
    assert set(doc["peripherals"]) == set(peripherals)
    for pname, pdef in peripherals.items():
        got = doc["peripherals"][pname]
        assert got["base_addr"] == pdef["base_addr"]
        assert got["description"] == pdef["description"]
        assert set(got["registers"]) == set(pdef["registers"])
        for rname, rdef in pdef["registers"].items():
            g = got["registers"][rname]
            assert g["addr"] == rdef["addr"]
            assert g["size"] == rdef["size"]
            assert g["type"] == rdef["type"]
            assert g["description"] == rdef["description"]


def test_field_resolution_matches_v1_mapping(doc, v1):
    """Each register's fields match v1's generic-name bitfield lookup."""
    peripherals, bitfields = v1
    for pname, pdef in peripherals.items():
        generic = pname.rstrip("0123456789")
        for rname in pdef["registers"]:
            block = bitfields.get("%s_%s" % (generic, rname))
            got_fields = doc["peripherals"][pname]["registers"][rname]["fields"]
            if not block:
                assert got_fields == {}, "%s.%s should have no fields" % (pname, rname)
                continue
            assert set(got_fields) == set(block)
            for fname, finfo in block.items():
                expect_bits = finfo["bits"]
                expect_lsb = expect_bits[0] if isinstance(expect_bits, list) else expect_bits
                g = got_fields[fname]
                assert g["lsb"] == expect_lsb
                assert g["width"] == finfo["width"]
                assert g["desc"] == finfo["desc"]
                if finfo["values"] is None:
                    assert g["values"] is None
                else:
                    assert g["values"] == {str(k): v for k, v in finfo["values"].items()}


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------
def test_regeneration_is_byte_identical():
    with open(JSON_PATH, "rb") as fh:
        checked_in = fh.read()
    fd, tmp = tempfile.mkstemp(suffix=".json")
    os.close(fd)
    try:
        subprocess.check_call([sys.executable, GEN_PATH, "-o", tmp])
        with open(tmp, "rb") as fh:
            regenerated = fh.read()
    finally:
        os.remove(tmp)
    assert regenerated == checked_in, "gen_registers.py output drifted from registers.json"
