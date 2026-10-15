# nightjar-hack - quickstart

An overlay that gives the nightjar BLE listening post the ability to send
payloads out over the network and Bluetooth, without disturbing the
receive-only scanning it was built around.

## 60 seconds

    # 1. get the upstream repo (nothing was uploaded; just clone)
    git clone https://github.com/chasebryan/nightjar
    cd nightjar

    # 2. lay the overlay on top
    python3 /path/to/nightjar-hack/apply_overlay.py .

    # 3. install
    pip install -e .
    pip install 'nightjar[tx]'      # only needed for ble:// and ble-gatt://

    # 4. try it
    nightjar send --help
    nightjar send tcp://127.0.0.1:9000 --payload "hello" --dry-run
    nightjar serve --tcp 9000

Then, in a second terminal:

    nightjar send tcp://127.0.0.1:9000 --payload "hello from the other side" --read

The first terminal prints the hexdump and answers.

## Single-file route

If you would rather not unzip anything, use nightjar-hack-single.py: it
writes the same files into the checkout and then calls apply_overlay.py.

## What it adds

    nightjar send TARGET [...]     payload out: tcp, udp, tls, http(s), ble, ble-gatt, ble-write
    nightjar serve [...]           payload in: tcp, udp, http, optional ble-gatt

## What it does not do

It does not change how scanning works, does not touch the log format, and
does not add a dependency to the default install. Network sending is pure
standard library. BLE writes reuse the `bleak` that scanning already needs.
Only the peripheral role (broadcasting / GATT server) pulls in the optional
`bless`, and only if you ask for it.

## Uninstall

    git checkout nightjar/cli.py pyproject.toml nightjar/__init__.py
    rm nightjar/send.py

Nothing was committed, so `git status` shows the overlay as your working
tree changes and `git diff` shows exactly the six edits.
