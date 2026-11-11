#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.vinayjagtap.mynotes.savedState
store=/tmp/MyNotes-self.store
rm -f $store $store-shm $store-wal
APP_STORE=$store ~/Applications/MyNotes.app/Contents/MacOS/MyNotes --selftest
