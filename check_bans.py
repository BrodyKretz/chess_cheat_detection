"""Asks the Lichess API which players from a CSV were later marked for cheating.
Run after pipeline.sql: python3 check_bans.py suspects.csv control.csv
"""
import csv
import json
import sys
import urllib.request


def lookup(names):
    """Returns a dict of lowercase username -> Lichess user object, 300 names per request."""
    users = {}
    for i in range(0, len(names), 300):
        batch = ",".join(names[i:i + 300]).encode()
        request = urllib.request.Request("https://lichess.org/api/users", data=batch, headers={"Content-Type": "text/plain"})
        for user in json.load(urllib.request.urlopen(request)):
            users[user["id"]] = user
    return users


def check(path):
    names = [row["player"] for row in csv.DictReader(open(path))]
    users = lookup(names)
    marked = sum(1 for name in names if users.get(name.lower(), {}).get("tosViolation"))
    closed = sum(1 for name in names if users.get(name.lower(), {}).get("disabled"))
    print(f"{path}: {len(names)} players, {marked} marked for cheating ({100 * marked / len(names):.1f}%), {closed} closed accounts")


for path in sys.argv[1:]:
    check(path)
