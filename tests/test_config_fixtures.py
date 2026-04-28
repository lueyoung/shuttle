#!/usr/bin/env python3
import glob
import json
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
LINE_RE = re.compile(r"^(#?)[ \t]*([^ \t=]+)[ \t=]+(.*)$")
SUPPORTED_WINDOW_MODES = {"tab", "new", "current", "virtual"}


def load_json(path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def split_include_paths(value):
    paths = []
    for raw in value.split():
        raw = raw.strip()
        if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "'\"":
            raw = raw[1:-1]
        if raw:
            paths.append(raw)
    return paths


def expand_include_paths(value, base_file):
    expanded = []
    base_dir = base_file.parent
    for include_path in split_include_paths(value):
        path = pathlib.Path(include_path).expanduser()
        if not path.is_absolute():
            path = base_dir / include_path

        path_text = str(path)
        if any(char in path_text for char in "*?["):
            expanded.extend(pathlib.Path(match) for match in glob.glob(path_text))
        else:
            expanded.append(path)
    return expanded


def parse_ssh_config(path, visited=None):
    path = pathlib.Path(path).expanduser().resolve()
    visited = visited or set()
    if path in visited or not path.exists():
        return {}
    visited.add(path)

    servers = {}
    current_key = None
    for line in path.read_text(encoding="utf-8").splitlines():
        match = LINE_RE.match(line.strip())
        if not match:
            continue

        is_comment = match.group(1) == "#"
        first = match.group(2)
        second = match.group(3)

        if is_comment and current_key and first.startswith("shuttle."):
            servers[current_key][first[8:]] = second

        if is_comment:
            continue

        directive = first.lower()
        if directive == "include":
            for include_path in expand_include_paths(second, path):
                servers.update(parse_ssh_config(include_path, visited))
            continue

        if directive == "host":
            aliases = [alias for alias in second.split() if alias]
            current_key = aliases[0] if aliases else None
            if current_key:
                servers[current_key] = {}

    return servers


def collect_leaf_items(items):
    leaf_items = []
    for item in items:
        if not isinstance(item, dict):
            continue
        if isinstance(item.get("name"), str) and isinstance(item.get("cmd"), str):
            leaf_items.append(item)
            continue
        for value in item.values():
            if isinstance(value, list):
                leaf_items.extend(collect_leaf_items(value))
    return leaf_items


def collect_leaf_names(items):
    return [item["name"] for item in collect_leaf_items(items)]


class ConfigFixtureTests(unittest.TestCase):
    def test_default_config_is_valid_json_with_hosts_array(self):
        config = load_json(ROOT / "Shuttle" / "shuttle.default.json")
        self.assertIsInstance(config, dict)
        self.assertIsInstance(config.get("hosts"), list)
        self.assertNotIn("iTerm_version", config)

    def test_test_config_is_valid_json_with_nested_menu_items(self):
        config = load_json(ROOT / "tests" / ".shuttle.json")
        names = collect_leaf_names(config["hosts"])
        self.assertIn("Main Item", names)
        self.assertIn("Submenu Item #3.1.1", names)

    def test_window_modes_and_url_type_are_documented_in_fixtures(self):
        default_config = load_json(ROOT / "Shuttle" / "shuttle.default.json")
        test_config = load_json(ROOT / "tests" / ".shuttle.json")
        self.assertIn(default_config.get("open_in"), SUPPORTED_WINDOW_MODES)
        self.assertIn(test_config.get("open_in"), SUPPORTED_WINDOW_MODES)

        leaf_items = collect_leaf_items(test_config["hosts"])
        url_items = [item for item in leaf_items if item.get("type") == "url"]
        self.assertTrue(url_items)
        self.assertTrue(all(item["cmd"].startswith(("http://", "https://", "file://", "ssh://")) for item in url_items))
        self.assertTrue(any("¬_¬" in item["cmd"] for item in leaf_items))

        for item in leaf_items:
            if "inTerminal" in item:
                self.assertIn(item["inTerminal"], SUPPORTED_WINDOW_MODES)

    def test_ssh_config_include_and_shuttle_comments(self):
        servers = parse_ssh_config(ROOT / "tests" / ".ssh" / "config")
        self.assertIn("included.example.com", servers)
        self.assertEqual(servers["dev01.example.net"]["name"], "Work/dev01.example.net (my dev box)")
        self.assertEqual(servers["test02.example.net"]["name"], "Work/Production/test02.example.net (database)")


if __name__ == "__main__":
    unittest.main()
