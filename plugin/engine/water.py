#!/usr/bin/env python3
"""
water.py - the Thirsty Claude engine.

Turns Claude Code token usage into an estimate of the water a request consumed,
keeps a running ledger, and unlocks milestones.

Single source of truth for both halves of the project:
  * the Claude Code plugin (hooks call this to rewrite the spinner verb)
  * WaterBar.app (the menu bar reads the state this writes)

Everything here is an ESTIMATE built from public figures. See model.json and the
README for where the numbers come from and how to change them.

Python 3.9+, standard library only.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from collections import deque
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
CLAUDE_DIR = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
WATER_DIR = os.path.join(CLAUDE_DIR, "water")
PROJECTS_DIR = os.path.join(CLAUDE_DIR, "projects")

MODEL_PATH = os.path.join(WATER_DIR, "model.json")
LEDGER_PATH = os.path.join(WATER_DIR, "ledger.jsonl")
CURSOR_PATH = os.path.join(WATER_DIR, "cursor.json")
STATE_PATH = os.path.join(WATER_DIR, "state.json")
CONFIG_PATH = os.path.join(WATER_DIR, "config.json")
LOCK_PATH = os.path.join(WATER_DIR, ".lock")

# --------------------------------------------------------------------------
# The estimate model
# --------------------------------------------------------------------------
# Energy is per 1,000 tokens, in watt-hours, at the accelerator + server level.
# PUE then covers datacenter overhead, and two water intensities convert energy
# to litres: on-site evaporative cooling, and the water the grid spent making
# the electricity in the first place.
#
# Sources for the defaults (all public, all rounded, all arguable):
#   - Google, "Measuring the environmental impact of AI inference" (2025):
#     median Gemini text prompt ~0.24 Wh, ~0.26 mL water. Anchors the low end.
#   - Li et al., "Making AI Less Thirsty" (2023): GPT-3 scale inference,
#     ~500 mL per 10-50 medium responses. Anchors the high end.
#   - Uptime Institute / Lawrence Berkeley National Lab: US datacenter on-site
#     water use efficiency ~1.8 L/kWh; grid electricity water intensity
#     ~3.1 L/kWh.
#   - Hyperscale PUE ~1.1.
#
# Output tokens cost far more than input tokens: prefill runs the whole prompt
# through in one massively parallel pass, while each output token is its own
# sequential forward pass. Cache reads are cheaper still - the KV state is
# already computed, it just has to be moved.

DEFAULT_MODEL = {
    "version": 1,
    "_comment": "Watt-hours per 1,000 tokens, per model tier. Edit freely.",
    "energy_wh_per_1k": {
        "opus":    {"output": 3.00, "input": 0.100, "cache_write": 0.100, "cache_read": 0.015},
        "sonnet":  {"output": 1.10, "input": 0.040, "cache_write": 0.040, "cache_read": 0.006},
        "fable":   {"output": 0.60, "input": 0.022, "cache_write": 0.022, "cache_read": 0.004},
        "haiku":   {"output": 0.30, "input": 0.012, "cache_write": 0.012, "cache_read": 0.002},
        "unknown": {"output": 1.10, "input": 0.040, "cache_write": 0.040, "cache_read": 0.006},
    },
    "pue": 1.10,
    "water_l_per_kwh": {
        "onsite_cooling": 1.80,
        "offsite_electricity": 3.10,
    },
    "web_search_wh": 0.30,
}

DEFAULT_CONFIG = {
    "spinner": {
        "enabled": True,
        # Which settings file the spinner verbs get written into.
        # "user" -> ~/.claude/settings.json, "user-local" -> ~/.claude/settings.local.json
        "settings_target": "user",
        # "replace" swaps out Claude's whole verb list; "append" mixes water
        # verbs in with Pondering / Percolating / Noodling.
        "mode": "replace",
        "show_session_total": True,
    },
    "notify_on_milestone": True,
}

# Verb templates. {amount} is the water for the most recent request.
VERB_TEMPLATES = [
    "Evaporating {amount}",
    "Boiling off {amount}",
    "Drinking {amount}",
    "Sipping {amount}",
    "Guzzling {amount}",
    "Slurping {amount}",
    "Chugging {amount}",
    "Draining {amount}",
    "Misting {amount}",
    "Vaporizing {amount}",
    "Sweating out {amount}",
    "Desalinating {amount}",
    "Condensing {amount}",
    "Wasting {amount}",
    "Steaming {amount}",
    "Decanting {amount}",
]

# Cumulative milestones, in millilitres.
MILESTONES = [
    (1,             "\U0001F4A7", "First Drop",          "One millilitre. It begins."),
    (10,            "\U0001F9EA", "Eye Dropper",         "10 mL. A pipette's worth of thinking."),
    (50,            "☕",     "Espresso Shot",       "50 mL. Enough to pull a single shot."),
    (250,           "\U0001F943", "A Glass of Water",    "250 mL. You could have just had a drink."),
    (500,           "\U0001F964", "The Bottle",          "500 mL. One standard bottle of water."),
    (1000,          "\U0001F4A6", "Litre Club",          "1 L. Officially measurable in litres now."),
    (3785,          "\U0001FAA3", "Gallon Guzzler",      "3.79 L. One US gallon."),
    (6000,          "\U0001F6BD", "Toilet Flush",        "6 L. One modern low-flow flush."),
    (15000,         "\U0001F37D", "Dishwasher Cycle",    "15 L. A full eco cycle."),
    (50000,         "\U0001F6BF", "Five-Minute Shower",  "50 L. One shower, start to finish."),
    (65000,         "\U0001F9FA", "Laundry Load",        "65 L. One wash of a full machine."),
    (150000,        "\U0001F6C1", "Full Bathtub",        "150 L. Filled to the overflow."),
    (310000,        "\U0001F3E0", "One Person, One Day", "310 L. Average household use, per person, per day."),
    (1000000,       "\U0001F9CA", "Cubic Metre",         "1,000 L. One tonne of water."),
    (2700000,       "\U0001F455", "Cotton T-Shirt",      "2,700 L. What it takes to grow and make one shirt."),
    (7600000,       "\U0001F456", "One Pair of Jeans",   "7,600 L. Denim is thirsty."),
    (15000000,      "\U0001F404", "One Kilo of Beef",    "15,000 L. The heavyweight of food footprints."),
    (50000000,      "\U0001F69B", "Tanker Truck",        "50,000 L. A full road tanker."),
    (100000000,     "\U0001F3D6", "Backyard Pool",       "100,000 L. Above ground, vinyl liner, questionable filter."),
    (600000000,     "\U0001F3E2", "Water Tower",         "600,000 L. A small town's buffer."),
    (2500000000,    "\U0001F3CA", "Olympic Pool",        "2,500,000 L. Fifty metres of regret."),
    (25000000000,   "\U0001F30A", "Reservoir",           "25,000,000 L. At this point, please stop."),
]

MODEL_TIER_PATTERNS = [
    (re.compile(r"opus", re.I), "opus"),
    (re.compile(r"sonnet", re.I), "sonnet"),
    (re.compile(r"fable", re.I), "fable"),
    (re.compile(r"haiku", re.I), "haiku"),
]


# --------------------------------------------------------------------------
# Small IO helpers
# --------------------------------------------------------------------------

def ensure_dir():
    os.makedirs(WATER_DIR, exist_ok=True)


def read_json(path, fallback):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return fallback


def write_json_atomic(path, data):
    ensure_dir()
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def deep_merge(base, override):
    """Fill in anything the user's file left out, without stomping what it has."""
    out = dict(base)
    for key, val in (override or {}).items():
        if isinstance(val, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], val)
        else:
            out[key] = val
    return out


def load_model():
    if not os.path.exists(MODEL_PATH):
        write_json_atomic(MODEL_PATH, DEFAULT_MODEL)
        return DEFAULT_MODEL
    return deep_merge(DEFAULT_MODEL, read_json(MODEL_PATH, {}))


def load_config():
    if not os.path.exists(CONFIG_PATH):
        write_json_atomic(CONFIG_PATH, DEFAULT_CONFIG)
        return DEFAULT_CONFIG
    return deep_merge(DEFAULT_CONFIG, read_json(CONFIG_PATH, {}))


class Lock:
    """Best-effort exclusive lock so two hooks firing at once can't interleave
    a read-modify-write of the ledger or of settings.json."""

    def __init__(self, timeout=5.0):
        self.timeout = timeout
        self.fd = None

    def __enter__(self):
        ensure_dir()
        deadline = time.time() + self.timeout
        while True:
            try:
                self.fd = os.open(LOCK_PATH, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                return self
            except FileExistsError:
                # Reap a lock left behind by a crashed process.
                try:
                    if time.time() - os.path.getmtime(LOCK_PATH) > 30:
                        os.unlink(LOCK_PATH)
                        continue
                except OSError:
                    pass
                if time.time() > deadline:
                    return self  # proceed unlocked rather than hang a hook
                time.sleep(0.05)

    def __exit__(self, *exc):
        if self.fd is not None:
            os.close(self.fd)
            try:
                os.unlink(LOCK_PATH)
            except OSError:
                pass
        return False


# --------------------------------------------------------------------------
# The math
# --------------------------------------------------------------------------

def model_tier(model_id):
    for pattern, tier in MODEL_TIER_PATTERNS:
        if pattern.search(model_id or ""):
            return tier
    return "unknown"


def water_ml(usage, model_id, model):
    """Millilitres of water for one API request."""
    tier = model_tier(model_id)
    rates = model["energy_wh_per_1k"].get(tier, model["energy_wh_per_1k"]["unknown"])

    out_tok = usage.get("output_tokens", 0) or 0
    in_tok = usage.get("input_tokens", 0) or 0
    cw_tok = usage.get("cache_creation_input_tokens", 0) or 0
    cr_tok = usage.get("cache_read_input_tokens", 0) or 0

    wh = (
        out_tok * rates["output"]
        + in_tok * rates["input"]
        + cw_tok * rates["cache_write"]
        + cr_tok * rates["cache_read"]
    ) / 1000.0

    server = usage.get("server_tool_use") or {}
    searches = (server.get("web_search_requests", 0) or 0) + (server.get("web_fetch_requests", 0) or 0)
    wh += searches * model.get("web_search_wh", 0.0)

    kwh = (wh / 1000.0) * model.get("pue", 1.1)
    l_per_kwh = sum(model["water_l_per_kwh"].values())
    return kwh * l_per_kwh * 1000.0, tier, (in_tok, out_tok, cw_tok, cr_tok)


def format_ml(ml):
    """Human units, chosen so the number stays readable at every scale."""
    if ml < 1:
        return "%.2f mL" % ml
    if ml < 10:
        return "%.1f mL" % ml
    if ml < 1000:
        return "%d mL" % round(ml)
    litres = ml / 1000.0
    if litres < 10:
        return "%.2f L" % litres
    if litres < 1000:
        return "%.1f L" % litres
    if litres < 1000000:
        return "%.1f kL" % (litres / 1000.0)
    # Not "ML": next to "500 mL" a capital M is a coin-flip for the reader.
    millions = litres / 1000000.0
    return "%s million L" % (("%.1f" % millions).rstrip("0").rstrip("."))


def milestone_for(total_ml):
    """(unlocked list, next milestone or None)."""
    unlocked = [m for m in MILESTONES if total_ml >= m[0]]
    remaining = [m for m in MILESTONES if total_ml < m[0]]
    return unlocked, (remaining[0] if remaining else None)


# --------------------------------------------------------------------------
# Scanning transcripts
# --------------------------------------------------------------------------
# Claude Code appends every API response to ~/.claude/projects/<slug>/<id>.jsonl
# with its token usage attached. We tail those files: a cursor remembers how far
# into each one we've read, so a scan only ever touches bytes that are new.
#
# The same requestId shows up on consecutive lines (one per content block), so a
# bounded ring of recently-counted ids does the deduping.

RECENT_ID_CAP = 50000


def _empty_state():
    return {
        "version": 1,
        "total_ml": 0.0,
        "requests": 0,
        "tokens": {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0},
        "by_day": {},
        "by_project": {},
        "by_model": {},
        "by_session": {},
        "unlocked": [],
        "first_seen": None,
        "last_seen": None,
        "updated_at": None,
    }


def _iter_transcripts():
    if not os.path.isdir(PROJECTS_DIR):
        return
    for root, _dirs, files in os.walk(PROJECTS_DIR):
        for name in files:
            if name.endswith(".jsonl"):
                yield os.path.join(root, name)


def _project_label(cwd, path):
    """Last two path components, so sibling `app` / `site` folders under
    different parents don't collapse into one bucket."""
    if not cwd:
        slug = os.path.basename(os.path.dirname(path))
        cwd = slug.replace("-", "/")
    parts = [p for p in cwd.rstrip("/").split("/") if p]
    if not parts:
        return cwd
    return "/".join(parts[-2:])


def scan(model=None, quiet=True, only_path=None):
    """Read whatever is new in the transcripts, extend the ledger, update state.

    `only_path` limits the walk to a single transcript - hooks pass the session's
    own file so a per-tool-call refresh stays in the single-digit milliseconds
    even when the full history is a gigabyte.

    Returns the state dict, plus the milestones this scan crossed.
    """
    model = model or load_model()
    ensure_dir()

    with Lock():
        cursor = read_json(CURSOR_PATH, {"files": {}, "recent_ids": []})
        state = read_json(STATE_PATH, None) or _empty_state()
        seen = deque(cursor.get("recent_ids", []), maxlen=RECENT_ID_CAP)
        seen_set = set(seen)

        before_ml = state["total_ml"]
        new_rows = []

        sources = [only_path] if only_path else _iter_transcripts()
        for path in sources:
            try:
                size = os.path.getsize(path)
            except OSError:
                continue
            entry = cursor["files"].get(path) or {"offset": 0}
            offset = entry.get("offset", 0)
            if size < offset:
                offset = 0  # file was rewritten (resume, rewind, compaction)
            if size == offset:
                continue

            # Binary mode: text-mode tell()/seek() cookies are opaque and can't
            # be stored as byte offsets across runs.
            try:
                with open(path, "rb") as fh:
                    fh.seek(offset)
                    raw = fh.read()
            except OSError:
                continue

            # Never consume a half-written trailing line.
            cut = raw.rfind(b"\n")
            if cut == -1:
                cursor["files"][path] = {"offset": offset}
                continue
            consumed = offset + cut + 1
            chunk = raw[: cut + 1].decode("utf-8", errors="replace")

            for line in chunk.splitlines():
                if not line.strip():
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if rec.get("type") != "assistant":
                    continue
                message = rec.get("message") or {}
                usage = message.get("usage")
                if not usage:
                    continue
                model_id = message.get("model") or ""
                if not model_id or model_id == "<synthetic>":
                    continue
                req_id = rec.get("requestId") or message.get("id") or rec.get("uuid")
                if not req_id or req_id in seen_set:
                    continue
                seen_set.add(req_id)
                if len(seen) == seen.maxlen:
                    seen_set.discard(seen[0])
                seen.append(req_id)

                ml, tier, toks = water_ml(usage, model_id, model)
                ts = rec.get("timestamp")
                new_rows.append({
                    "ts": ts,
                    "id": req_id,
                    "s": rec.get("sessionId"),
                    "p": _project_label(rec.get("cwd"), path),
                    "m": tier,
                    "ml": round(ml, 4),
                    "tok": list(toks),
                })

            cursor["files"][path] = {"offset": consumed}

        newly = []
        if new_rows:
            with open(LEDGER_PATH, "a", encoding="utf-8") as fh:
                for row in new_rows:
                    fh.write(json.dumps(row, separators=(",", ":")) + "\n")
            _apply_rows(state, new_rows)
            newly = _refresh_unlocked(state, before_ml)

        state["updated_at"] = datetime.now(timezone.utc).isoformat()
        cursor["recent_ids"] = list(seen)
        write_json_atomic(STATE_PATH, state)
        write_json_atomic(CURSOR_PATH, cursor)

    if not quiet:
        print(json.dumps({"added": len(new_rows), "total_ml": state["total_ml"],
                          "unlocked": newly}, indent=2))
    return state, newly


def _bump(bucket, key, ml, requests=1):
    if key is None:
        return
    cell = bucket.get(key) or {"ml": 0.0, "requests": 0}
    cell["ml"] = round(cell["ml"] + ml, 4)
    cell["requests"] += requests
    bucket[key] = cell


def _local_day(ts):
    if not ts:
        return datetime.now().strftime("%Y-%m-%d")
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return dt.astimezone().strftime("%Y-%m-%d")
    except Exception:
        return datetime.now().strftime("%Y-%m-%d")


def _apply_rows(state, rows):
    for row in rows:
        ml = row["ml"]
        state["total_ml"] = round(state["total_ml"] + ml, 4)
        state["requests"] += 1
        tin, tout, tcw, tcr = row["tok"]
        state["tokens"]["input"] += tin
        state["tokens"]["output"] += tout
        state["tokens"]["cache_write"] += tcw
        state["tokens"]["cache_read"] += tcr
        _bump(state["by_day"], _local_day(row.get("ts")), ml)
        _bump(state["by_project"], row.get("p"), ml)
        _bump(state["by_model"], row.get("m"), ml)
        _bump(state["by_session"], row.get("s"), ml)
        ts = row.get("ts")
        if ts:
            if not state["first_seen"] or ts < state["first_seen"]:
                state["first_seen"] = ts
            if not state["last_seen"] or ts > state["last_seen"]:
                state["last_seen"] = ts

    # Keep the maps from growing without bound.
    if len(state["by_day"]) > 400:
        for key in sorted(state["by_day"])[:-400]:
            del state["by_day"][key]
    if len(state["by_session"]) > 5000:
        # dicts keep insertion order, so this drops the least recently touched.
        state["by_session"] = dict(list(state["by_session"].items())[-5000:])


def _refresh_unlocked(state, before_ml):
    unlocked, _ = milestone_for(state["total_ml"])
    names = [m[2] for m in unlocked]
    newly = [m for m in unlocked if m[0] > before_ml]
    state["unlocked"] = names
    if newly:
        log = read_json(os.path.join(WATER_DIR, "achievements.json"), [])
        for threshold, icon, name, blurb in newly:
            log.append({
                "name": name, "icon": icon, "blurb": blurb,
                "threshold_ml": threshold,
                "at": datetime.now(timezone.utc).isoformat(),
            })
        write_json_atomic(os.path.join(WATER_DIR, "achievements.json"), log)
    return [{"icon": m[1], "name": m[2], "blurb": m[3], "threshold_ml": m[0]} for m in newly]


def rebuild():
    """Recompute state.json from the ledger. Use after editing model.json --
    note this re-prices nothing; it re-totals the millilitres already recorded."""
    state = _empty_state()
    rows = []
    if os.path.exists(LEDGER_PATH):
        with open(LEDGER_PATH, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except Exception:
                    continue
    _apply_rows(state, rows)
    _refresh_unlocked(state, -1)
    state["updated_at"] = datetime.now(timezone.utc).isoformat()
    write_json_atomic(STATE_PATH, state)
    return state


# --------------------------------------------------------------------------
# Session view
# --------------------------------------------------------------------------

def _tail_lines(path, max_bytes=131072):
    try:
        size = os.path.getsize(path)
    except OSError:
        return []
    with open(path, "rb") as fh:
        fh.seek(max(0, size - max_bytes))
        raw = fh.read()
    if size > max_bytes:
        raw = raw.split(b"\n", 1)[-1]
    return raw.decode("utf-8", errors="replace").splitlines()


def session_stats(state, session_id):
    """Totals for one session, plus the cost of its most recent request."""
    cell = (state.get("by_session") or {}).get(session_id) or {"ml": 0.0, "requests": 0}
    last_ml = None
    if session_id and os.path.exists(LEDGER_PATH):
        for line in reversed(_tail_lines(LEDGER_PATH)):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if row.get("s") == session_id:
                last_ml = row.get("ml")
                break
    avg = (cell["ml"] / cell["requests"]) if cell["requests"] else None
    return {"total_ml": cell["ml"], "requests": cell["requests"],
            "last_ml": last_ml, "avg_ml": avg}


def latest_session():
    """The session that most recently made a request, per the ledger tail."""
    if not os.path.exists(LEDGER_PATH):
        return None
    for line in reversed(_tail_lines(LEDGER_PATH, 16384)):
        if not line.strip():
            continue
        try:
            return json.loads(line).get("s")
        except Exception:
            continue
    return None


def today_ml(state):
    key = datetime.now().strftime("%Y-%m-%d")
    return ((state.get("by_day") or {}).get(key) or {"ml": 0.0})["ml"]


# --------------------------------------------------------------------------
# The spinner
# --------------------------------------------------------------------------
# Claude Code picks a spinner verb at random from settings.spinnerVerbs at the
# start of each turn, and watches its settings files for changes. So rewriting
# that list after every request makes the spinner report live numbers.
#
# We can't know what the request about to run will cost, so the number shown is
# the one the *previous* request actually cost, jittered a little. It is a
# nowcast, not a prediction. That is the honest version of this joke.

def settings_path_for(target):
    if target == "user-local":
        return os.path.join(CLAUDE_DIR, "settings.local.json")
    if target and os.path.isabs(target):
        return target
    return os.path.join(CLAUDE_DIR, "settings.json")


def build_verbs(base_ml, total_ml, count=12, show_total=True):
    import random

    verbs = []
    templates = random.sample(VERB_TEMPLATES, min(count, len(VERB_TEMPLATES)))
    total_txt = format_ml(total_ml)
    for i, tmpl in enumerate(templates):
        jitter = base_ml * (0.85 + random.random() * 0.30)
        verb = tmpl.format(amount=format_ml(jitter))
        if show_total and total_ml > 0 and i % 4 == 3:
            verb = "%s · %s this session" % (verb, total_txt)
        verbs.append(verb)
    return verbs


def apply_spinner(session_id, config=None, state=None, force=False):
    """Rewrite spinnerVerbs in the target settings file. Returns the verbs used."""
    config = config or load_config()
    spin = config["spinner"]
    if not spin.get("enabled", True):
        return None

    state = state if state is not None else (read_json(STATE_PATH, None) or _empty_state())
    sess = session_stats(state, session_id)

    base = sess["last_ml"] or sess["avg_ml"]
    if not base:
        base = (state["total_ml"] / state["requests"]) if state["requests"] else 8.0

    # Claude Code re-reads its settings on every change, so don't rewrite the
    # file when nothing visible would move. Rounding is what the user sees, so
    # rounding is what we compare.
    memo_path = os.path.join(WATER_DIR, "spinner.json")
    signature = "%s|%s|%s" % (format_ml(base), format_ml(sess["total_ml"]), session_id or "")
    if read_json(memo_path, {}).get("signature") == signature and not force:
        return None

    verbs = build_verbs(base, sess["total_ml"], show_total=spin.get("show_session_total", True))
    path = settings_path_for(spin.get("settings_target", "user"))

    with Lock():
        settings = read_json(path, None)
        if settings is None:
            if os.path.exists(path):
                return None  # malformed file - leave it alone
            settings = {}
        backup = path + ".before-water"
        if not os.path.exists(backup) and os.path.exists(path):
            try:
                write_json_atomic(backup, settings)
            except Exception:
                pass
        settings["spinnerVerbs"] = {
            "mode": spin.get("mode", "replace"),
            "verbs": verbs,
        }
        write_json_atomic(path, settings)
        write_json_atomic(memo_path, {"signature": signature, "at": time.time()})
    return verbs


def clear_spinner(config=None):
    config = config or load_config()
    path = settings_path_for(config["spinner"].get("settings_target", "user"))
    with Lock():
        settings = read_json(path, None)
        if not settings or "spinnerVerbs" not in settings:
            return False
        del settings["spinnerVerbs"]
        write_json_atomic(path, settings)
        try:
            os.unlink(os.path.join(WATER_DIR, "spinner.json"))
        except OSError:
            pass
    return True


# --------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------

EQUIVALENTS = [
    (500, "bottle of water", "bottles of water"),
    (250, "glass of water", "glasses of water"),
    (6000, "toilet flush", "toilet flushes"),
    (50000, "shower", "showers"),
    (150000, "bathtub", "bathtubs"),
]


def equivalents(total_ml):
    out = []
    for size, one, many in EQUIVALENTS:
        n = total_ml / size
        if n >= 0.75:
            label = one if 0.75 <= n < 1.5 else many
            out.append("%s %s" % (("%.1f" % n).rstrip("0").rstrip("."), label))
    return out[-3:] if out else []


def progress_bar(fraction, width=24):
    filled = int(round(max(0.0, min(1.0, fraction)) * width))
    return "█" * filled + "░" * (width - filled)


def render_report(state, session_id=None):
    total = state["total_ml"]
    unlocked, nxt = milestone_for(total)
    lines = []
    lines.append("## \U0001F4A7 Water ledger")
    lines.append("")
    lines.append("**%s** across %s requests" % (format_ml(total), "{:,}".format(state["requests"])))
    eq = equivalents(total)
    if eq:
        lines.append("_about %s_" % ", or ".join(eq))
    lines.append("")

    lines.append("| | water | requests |")
    lines.append("|---|---:|---:|")
    lines.append("| Today | %s | %s |" % (
        format_ml(today_ml(state)),
        "{:,}".format(((state.get("by_day") or {}).get(datetime.now().strftime("%Y-%m-%d")) or {"requests": 0})["requests"]),
    ))
    if session_id:
        sess = session_stats(state, session_id)
        lines.append("| This session | %s | %s |" % (format_ml(sess["total_ml"]), "{:,}".format(sess["requests"])))
        if sess["last_ml"] is not None:
            lines.append("| Last request | %s | |" % format_ml(sess["last_ml"]))
    lines.append("| All time | %s | %s |" % (format_ml(total), "{:,}".format(state["requests"])))
    lines.append("")

    if nxt:
        threshold, icon, name, blurb = nxt
        prev = unlocked[-1][0] if unlocked else 0
        span = threshold - prev
        frac = (total - prev) / span if span > 0 else 0.0
        lines.append("**Next milestone** %s %s - %s" % (icon, name, format_ml(threshold)))
        lines.append("`%s` %d%%  (%s to go)" % (progress_bar(frac), round(frac * 100), format_ml(threshold - total)))
    else:
        lines.append("**Every milestone unlocked.** There is nothing left to pour.")
    lines.append("")

    if unlocked:
        lines.append("**Unlocked (%d/%d)**" % (len(unlocked), len(MILESTONES)))
        lines.append("")
        for threshold, icon, name, blurb in unlocked[-6:]:
            lines.append("- %s **%s** - %s" % (icon, name, blurb))
        if len(unlocked) > 6:
            lines.append("- _...and %d earlier_" % (len(unlocked) - 6))
        lines.append("")

    projects = sorted((state.get("by_project") or {}).items(), key=lambda kv: -kv[1]["ml"])[:5]
    if projects:
        lines.append("**Thirstiest projects**")
        lines.append("")
        for name, cell in projects:
            lines.append("- `%s` - %s" % (name, format_ml(cell["ml"])))
        lines.append("")

    models = sorted((state.get("by_model") or {}).items(), key=lambda kv: -kv[1]["ml"])
    if models:
        lines.append("**By model** " + " · ".join(
            "%s %s" % (name, format_ml(cell["ml"])) for name, cell in models))
        lines.append("")

    lines.append("_Estimated from token counts. Not measured. See `~/.claude/water/model.json`._")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def _read_stdin_json():
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def cmd_hook():
    """Fired after every tool result and at the end of every turn. Keeps the
    ledger current and rewrites the spinner verb with what the last request
    actually cost. Never allowed to fail loudly - a broken hook is worse than a
    missing joke."""
    payload = _read_stdin_json()
    session_id = payload.get("session_id")
    transcript = payload.get("transcript_path")
    if transcript and not os.path.exists(transcript):
        transcript = None
    config = load_config()
    state, newly = scan(only_path=transcript)
    try:
        apply_spinner(session_id, config=config, state=state)
    except Exception:
        pass

    out = {"suppressOutput": True}
    if newly and config.get("notify_on_milestone", True):
        first = newly[-1]
        out["systemMessage"] = "%s  Milestone unlocked: %s - %s (total: %s)" % (
            first["icon"], first["name"], first["blurb"], format_ml(state["total_ml"]))
    print(json.dumps(out))


def cmd_statusline():
    payload = _read_stdin_json()
    state, _ = scan()
    sess = session_stats(state, payload.get("session_id"))
    _, nxt = milestone_for(state["total_ml"])
    parts = ["\U0001F4A7 %s session" % format_ml(sess["total_ml"]),
             "%s today" % format_ml(today_ml(state)),
             "%s all time" % format_ml(state["total_ml"])]
    if nxt:
        parts.append("next: %s %s" % (nxt[1], nxt[2]))
    print("  ".join(parts))


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "report"
    args = argv[2:]

    def opt(name, default=None):
        if name in args:
            i = args.index(name)
            if i + 1 < len(args):
                return args[i + 1]
        return default

    if cmd == "hook":
        cmd_hook()
    elif cmd == "statusline":
        cmd_statusline()
    elif cmd == "scan":
        scan(quiet=False)
    elif cmd == "rebuild":
        print(json.dumps({"total_ml": rebuild()["total_ml"]}, indent=2))
    elif cmd == "status":
        state, _ = scan(only_path=opt("--transcript"))
        state["today_ml"] = today_ml(state)
        sid = opt("--session")
        if sid:
            state["session"] = session_stats(state, sid)
        if "--refresh-spinner" in args:
            # Lets WaterBar keep the spinner current even when the plugin
            # isn't installed - just with a poll-interval lag instead of
            # updating the instant a request lands.
            try:
                apply_spinner(sid or latest_session(), state=state)
            except Exception:
                pass
        if "--compact" in args:
            # WaterBar polls this every few seconds; by_session can hold
            # thousands of rows it never reads.
            state.pop("by_session", None)
            days = state.get("by_day") or {}
            state["by_day"] = {k: days[k] for k in sorted(days)[-60:]}
            projects = sorted((state.get("by_project") or {}).items(),
                              key=lambda kv: -kv[1]["ml"])[:12]
            state["by_project"] = dict(projects)
        _, nxt = milestone_for(state["total_ml"])
        state["next_milestone"] = (
            {"threshold_ml": nxt[0], "icon": nxt[1], "name": nxt[2], "blurb": nxt[3]} if nxt else None
        )
        state["milestones"] = [
            {"threshold_ml": m[0], "icon": m[1], "name": m[2], "blurb": m[3],
             "unlocked": state["total_ml"] >= m[0]}
            for m in MILESTONES
        ]
        print(json.dumps(state, indent=2))
    elif cmd == "report":
        state, _ = scan()
        print(render_report(state, opt("--session")))
    elif cmd == "spinner":
        state, _ = scan()
        verbs = apply_spinner(opt("--session"), state=state, force=True)
        print(json.dumps({"verbs": verbs}, indent=2))
    elif cmd == "spinner-off":
        config = load_config()
        config["spinner"]["enabled"] = False
        write_json_atomic(CONFIG_PATH, config)
        print("removed" if clear_spinner(config) else "nothing to remove")
    elif cmd == "spinner-on":
        config = load_config()
        config["spinner"]["enabled"] = True
        write_json_atomic(CONFIG_PATH, config)
        state, _ = scan()
        apply_spinner(opt("--session"), config=config, state=state, force=True)
        print("spinner verbs enabled")
    elif cmd == "reset":
        for path in (LEDGER_PATH, CURSOR_PATH, STATE_PATH,
                     os.path.join(WATER_DIR, "achievements.json")):
            try:
                os.unlink(path)
            except OSError:
                pass
        print("ledger reset - back to zero")
    elif cmd == "paths":
        print(json.dumps({"water_dir": WATER_DIR, "ledger": LEDGER_PATH,
                          "state": STATE_PATH, "model": MODEL_PATH,
                          "config": CONFIG_PATH}, indent=2))
    else:
        print(__doc__)
        print("commands: scan status report spinner spinner-on spinner-off "
              "statusline hook rebuild reset paths")
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as exc:  # never take the session down with us
        if len(sys.argv) > 1 and sys.argv[1] in ("hook", "statusline"):
            print("" if sys.argv[1] == "statusline" else "{}")
            sys.exit(0)
        sys.stderr.write("water.py: %s\n" % exc)
        sys.exit(1)
