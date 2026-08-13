#!/usr/bin/env python3
"""A standing set of demo notes for testing layout, ageing and nesting.

    python3 Scripts/demo-data.py install    # back up your notes, then load these
    python3 Scripts/demo-data.py restore    # put your own notes back
    python3 Scripts/demo-data.py print      # write the JSON to stdout

Ages are stored as *days ago* and dated at generation time, so the set always
exercises all three traffic lights however long it sits in the repo. Note IDs are
derived from each note's path, so repeated installs produce identical files and a
diff between runs shows only what actually changed.

The board deliberately covers the awkward cases: one-word notes at the minimum
tile size, paragraphs that force a two-column tile, one note long enough to hit the
height cap and truncate, three levels of nesting, and notes at every age. It
installs three workspaces — a full one, a small one, and an empty one — so the
swipe, the dots and the empty state all have something to exercise.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import uuid
from datetime import datetime, timedelta, timezone

STORE = os.path.expanduser("~/Library/Application Support/NoteBubble/bubbles.json")
NAMESPACE = uuid.UUID("6f0d2a54-1f3b-4f2e-9a77-8f1c2b3d4e5f")

# (text, days ago, [children])
BOARD = [
    ("Bins", 0, []),
    ("Dentist", 0, []),
    ("Call Mum", 0, []),
    ("Gym", 1, []),
    ("Water the plants", 1, []),
    ("Reply to Sam about the weekend", 2, []),
    (
        "Kitchen shelves",
        4,
        [
            ("Measure the alcove", 4, []),
            ("Buy brackets — the 200mm ones, not the 150s I got last time", 3, []),
            (
                "Cut to length",
                2,
                [
                    ("Borrow the mitre saw from Tom", 2, []),
                    ("Sand the edges", 1, []),
                ],
            ),
        ],
    ),
    (
        "Plan Alice's birthday",
        5,
        [
            ("Book the restaurant", 5, []),
            ("Order the cake — chocolate, no nuts", 4, []),
            ("Ask everyone about dietary requirements", 3, []),
        ],
    ),
    (
        "Spanish game deploy",
        6,
        [
            ("Fix the auth redirect", 6, []),
            (
                "Postgres migration",
                9,
                [
                    ("Write the down migration too", 9, []),
                    ("Test it on staging first", 8, []),
                ],
            ),
            ("Update the README", 1, []),
        ],
    ),
    ("Book flights", 7, []),
    ("Cancel the gym trial before it renews on the 14th", 8, []),
    ("Renew passport", 12, []),
    ("Return the library books", 15, []),
    (
        "Tax return — dig out the receipts from the shoebox, the bank statements "
        "for the whole year, and whatever the accountant sent in April",
        30,
        [
            ("Find the shoebox", 30, []),
            ("Download bank statements", 22, []),
            ("Email the accountant back", 18, []),
        ],
    ),
    # Long enough to force a two-column tile and then truncate at the height cap —
    # the case that used to overflow its frame.
    (
        "Notes from the call: they want the onboarding flow reworked before the "
        "end of the quarter, the pricing page split into three tiers, and someone "
        "to own the migration off the old billing system. None of this is written "
        "down anywhere else, which is the actual problem.",
        3,
        [],
    ),
]


# A second board, deliberately small: switching to it should visibly resize the
# panel, and its notes must never appear on the first one.
ERRANDS = [
    ("Post office", 0, []),
    ("Pick up the dry cleaning", 2, []),
    ("Chase the parcel that says delivered but isn't", 9, []),
    (
        "Weekly shop",
        1,
        [
            ("Coffee", 1, []),
            ("Olive oil — the big tin", 1, []),
        ],
    ),
]

# (name, board) — the third is empty on purpose, so the empty state and a grey
# workspace dot are both on screen without having to make one by hand.
WORKSPACES = [
    ("Home", BOARD),
    ("Errands", ERRANDS),
    ("Someday", []),
]


def build(entries, path=()):
    now = datetime.now(timezone.utc)
    notes = []
    for index, (text, days, children) in enumerate(entries):
        here = path + (index,)
        created = now - timedelta(days=days, hours=index % 7)
        notes.append(
            {
                "id": str(uuid.uuid5(NAMESPACE, "/".join(map(str, here)))).upper(),
                "text": text,
                "createdAt": created.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "children": build(children, here),
            }
        )
    return notes


def count(notes):
    return sum(1 + count(note["children"]) for note in notes)


def document():
    """The whole file: workspaces, and which one opens.

    Workspace ids are derived from the name for the same reason note ids are
    derived from their path — installing twice produces byte-identical files.
    """
    workspaces = [
        {
            "id": str(uuid.uuid5(NAMESPACE, f"workspace/{name}")).upper(),
            "name": name,
            "notes": build(board, (index,)),
        }
        for index, (name, board) in enumerate(WORKSPACES)
    ]
    return {
        "version": 2,
        "workspaces": workspaces,
        "currentID": workspaces[0]["id"],
    }


def app_is_running():
    result = subprocess.run(["pgrep", "-f", "Note Bubble.app"], capture_output=True)
    return result.returncode == 0


def install(force):
    if app_is_running() and not force:
        sys.exit(
            "Note Bubble is running and would overwrite this on its next save.\n"
            "Quit it first (pkill -f 'Note Bubble.app'), or pass --force."
        )

    os.makedirs(os.path.dirname(STORE), exist_ok=True)
    if os.path.exists(STORE):
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = f"{STORE}.backup-{stamp}"
        shutil.copy2(STORE, backup)
        print(f"backed up your notes to {os.path.basename(backup)}")

    data = document()
    with open(STORE, "w") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
    total = sum(count(workspace["notes"]) for workspace in data["workspaces"])
    top = len(data["workspaces"][0]["notes"])
    print(
        f"installed {total} demo notes across {len(data['workspaces'])} workspaces "
        f"({top} at the top level of the first)"
    )


def restore():
    directory = os.path.dirname(STORE)
    backups = sorted(
        f for f in os.listdir(directory) if f.startswith("bubbles.json.backup-")
    )
    if not backups:
        sys.exit("no backup to restore")
    newest = os.path.join(directory, backups[-1])
    shutil.copy2(newest, STORE)
    print(f"restored {backups[-1]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["install", "restore", "print"])
    parser.add_argument("--force", action="store_true", help="install even if the app is running")
    args = parser.parse_args()

    if args.command == "print":
        print(json.dumps(document(), indent=2, sort_keys=True))
    elif args.command == "install":
        install(args.force)
    else:
        restore()


if __name__ == "__main__":
    main()
