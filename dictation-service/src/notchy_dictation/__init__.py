"""Notchy's local dictation service.

A small HTTP + WebSocket server that turns 16 kHz PCM from the Notchy apps into
text with an open-weights speech model running on this machine (Qwen3-ASR by
default). The apps never load a model themselves: they talk to this process at
the address set in their Settings, so the model can be swapped, or moved to a
machine with a GPU, without touching them.
"""

__version__ = "0.1.0"

# Bumped when a message changes shape. Sent in `ready` and in /health, so an app
# can say "update the service" rather than misreading a field.
PROTOCOL_VERSION = 1
