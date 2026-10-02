#!/usr/bin/env python3
"""Manage a private Minecraft identity source and its generated whitelist."""
import hashlib
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request
import uuid
from pathlib import Path


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def valid_name(name: str) -> None:
    if not (3 <= len(name) <= 16 and all(c.isascii() and (c.isalnum() or c == "_") for c in name)):
        fail(f"Invalid Minecraft name: {name}")


def load_whitelist(path: Path) -> list[dict[str, str]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"Cannot read whitelist {path}: {error}")
    if not isinstance(data, list):
        fail(f"Whitelist {path} must contain a JSON array.")
    for entry in data:
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str) or not isinstance(entry.get("uuid"), str):
            fail(f"Whitelist {path} contains an invalid entry.")
        try:
            uuid.UUID(entry["uuid"])
        except ValueError:
            fail(f"Whitelist {path} contains an invalid UUID: {entry['uuid']}")
    return data


def save_whitelist(path: Path, entries: list[dict[str, str]]) -> None:
    entries.sort(key=lambda entry: (entry["name"].casefold(), entry["uuid"]))
    payload = json.dumps(entries, indent=2) + "\n"

    try:
        if path.exists():
            # whitelist.json is bind-mounted into running containers. Rewriting
            # this existing file preserves its inode, so the mount sees updates.
            with path.open("w", encoding="utf-8") as handle:
                handle.write(payload)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(path, 0o644)
        else:
            fd, temporary = tempfile.mkstemp(
                prefix=".whitelist.", suffix=".json", dir=path.parent
            )
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    handle.write(payload)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.chmod(temporary, 0o644)
                os.replace(temporary, path)
            except OSError:
                try:
                    os.unlink(temporary)
                except OSError:
                    pass
                raise
    except OSError as error:
        fail(f"Cannot save whitelist {path}: {error}")

def offline_uuid(name: str) -> str:
    digest = bytearray(hashlib.md5(f"OfflinePlayer:{name}".encode("utf-8")).digest())
    digest[6] = (digest[6] & 0x0F) | 0x30
    digest[8] = (digest[8] & 0x3F) | 0x80
    return str(uuid.UUID(bytes=bytes(digest)))


def premium_uuid(name: str) -> str:
    url = f"https://api.minecraftservices.com/minecraft/profile/lookup/name/{name}"
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            data = json.load(response)
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError) as error:
        fail(f"Could not obtain Mojang UUID for {name}: {error}")
    profile_id = data.get("id") if isinstance(data, dict) else None
    if not isinstance(profile_id, str) or len(profile_id) != 32:
        fail(f"Mojang returned no usable UUID for {name}.")
    try:
        return str(uuid.UUID(profile_id))
    except ValueError:
        fail(f"Mojang returned an invalid UUID for {name}.")


def normal_uuid(value: object, field: str, name: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        fail(f"{field} for {name} must be a UUID or null.")
    try:
        return str(uuid.UUID(value))
    except ValueError:
        fail(f"{field} for {name} is not a valid UUID: {value}")


def load_identities(path: Path) -> list[dict[str, object]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"Cannot read identities {path}: {error}")
    if not isinstance(data, dict) or data.get("schema_version") != 1 or not isinstance(data.get("players"), list):
        fail("identities.json must contain schema_version 1 and a players array.")

    players: list[dict[str, object]] = []
    names: set[str] = set()
    for raw in data["players"]:
        if not isinstance(raw, dict) or not isinstance(raw.get("name"), str):
            fail("identities.json contains an invalid player.")
        name = raw["name"]
        valid_name(name)
        if name.casefold() in names:
            fail(f"identities.json contains {name} more than once.")
        names.add(name.casefold())
        offline = normal_uuid(raw.get("offline_uuid"), "offline_uuid", name)
        if offline != offline_uuid(name):
            fail(f"offline_uuid for {name} does not match the exact OfflinePlayer UUID.")
        premium = normal_uuid(raw.get("premium_uuid"), "premium_uuid", name)
        observed = normal_uuid(raw.get("observed_easyauth_uuid"), "observed_easyauth_uuid", name)
        allow_offline = raw.get("allow_offline_uuid")
        allow_premium = raw.get("allow_premium_uuid")
        if not isinstance(allow_offline, bool) or not isinstance(allow_premium, bool):
            fail(f"allow_offline_uuid and allow_premium_uuid for {name} must be true or false.")
        if allow_premium and premium is None:
            fail(f"{name} allows a premium UUID but no premium_uuid is recorded.")
        player: dict[str, object] = {
            "name": name,
            "offline_uuid": offline,
            "premium_uuid": premium,
            "observed_easyauth_uuid": observed,
            "allow_offline_uuid": allow_offline,
            "allow_premium_uuid": allow_premium,
        }
        if isinstance(raw.get("note"), str):
            player["note"] = raw["note"]
        players.append(player)
    return players


def save_identities(path: Path, players: list[dict[str, object]]) -> None:
    payload = {"schema_version": 1, "players": sorted(players, key=lambda player: str(player["name"]).casefold())}
    fd, temporary = tempfile.mkstemp(prefix=".identities.", suffix=".json", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except OSError as error:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        fail(f"Cannot save identities {path}: {error}")


def build_entries(players: list[dict[str, object]]) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    seen: dict[str, str] = {}
    for player in players:
        name = str(player["name"])
        for permitted, key in ((player["allow_offline_uuid"], "offline_uuid"), (player["allow_premium_uuid"], "premium_uuid")):
            if not permitted:
                continue
            entry_uuid = player[key]
            if not isinstance(entry_uuid, str):
                fail(f"{name} has no usable {key}.")
            other = seen.get(entry_uuid)
            if other is not None and other.casefold() != name.casefold():
                fail(f"UUID {entry_uuid} belongs to both {other} and {name}.")
            seen[entry_uuid] = name
            entries.append({"uuid": entry_uuid, "name": name})
    return entries


def player_for(players: list[dict[str, object]], name: str) -> dict[str, object] | None:
    return next((player for player in players if str(player["name"]).casefold() == name.casefold()), None)


def main(arguments: list[str]) -> None:
    if not arguments:
        fail("Missing command.")
    command = arguments[0]
    if command == "validate" and len(arguments) == 2:
        load_identities(Path(arguments[1]))
        return
    if command == "list" and len(arguments) == 2:
        print(json.dumps({"schema_version": 1, "players": load_identities(Path(arguments[1]))}, indent=2))
        return
    if command == "build" and len(arguments) == 3:
        players = load_identities(Path(arguments[1]))
        save_whitelist(Path(arguments[2]), build_entries(players))
        return
    if command == "audit" and len(arguments) == 3:
        expected = {(entry["name"], entry["uuid"]) for entry in build_entries(load_identities(Path(arguments[1])))}
        actual = {(entry["name"], entry["uuid"]) for entry in load_whitelist(Path(arguments[2]))}
        if expected != actual:
            fail("whitelist.json does not match identities.json; run mc-whitelist apply.")
        print("identities.json and whitelist.json match.")
        return
    if command == "migrate" and len(arguments) == 3:
        players: list[dict[str, object]] = []
        for entry in load_whitelist(Path(arguments[1])):
            name, entry_uuid = entry["name"], entry["uuid"]
            player = player_for(players, name)
            if player is None:
                player = {
                    "name": name,
                    "offline_uuid": offline_uuid(name),
                    "premium_uuid": None,
                    "observed_easyauth_uuid": None,
                    "allow_offline_uuid": False,
                    "allow_premium_uuid": False,
                    "note": "Migrated from the previous whitelist; verify before changing.",
                }
                players.append(player)
            if entry_uuid == player["offline_uuid"]:
                player["allow_offline_uuid"] = True
            elif player["premium_uuid"] in (None, entry_uuid):
                player["premium_uuid"] = entry_uuid
                player["allow_premium_uuid"] = True
            else:
                fail(f"Legacy whitelist has multiple non-offline UUIDs for {name}; refusing to guess.")
        save_identities(Path(arguments[2]), players)
        return
    if command == "add" and len(arguments) == 4:
        path, identity, name = Path(arguments[1]), arguments[2], arguments[3]
        valid_name(name)
        if identity not in ("offline", "premium"):
            fail("Identity must be premium or offline.")
        players = load_identities(path)
        player = player_for(players, name)
        if player is None:
            player = {
                "name": name,
                "offline_uuid": offline_uuid(name),
                "premium_uuid": None,
                "observed_easyauth_uuid": None,
                "allow_offline_uuid": False,
                "allow_premium_uuid": False,
            }
            players.append(player)
        if identity == "offline":
            player["allow_offline_uuid"] = True
        else:
            player["premium_uuid"] = premium_uuid(name)
            # A premium owner must also be able to enter this repository's
            # current online-mode=false environments before EasyAuth classifies
            # the session.
            player["allow_offline_uuid"] = True
            player["allow_premium_uuid"] = True
        save_identities(path, players)
        return
    if command == "remove" and len(arguments) == 4:
        path, name, identity = Path(arguments[1]), arguments[2], arguments[3]
        valid_name(name)
        if identity not in ("offline", "premium", "all"):
            fail("Identity must be premium, offline or all.")
        players = load_identities(path)
        player = player_for(players, name)
        if player is None:
            fail(f"No identity recorded for {name}.")
        if identity == "all":
            players.remove(player)
        elif identity == "offline":
            player["allow_offline_uuid"] = False
        else:
            player["allow_premium_uuid"] = False
        save_identities(path, players)
        return
    fail("Invalid whitelist-json.py command.")


if __name__ == "__main__":
    main(sys.argv[1:])
