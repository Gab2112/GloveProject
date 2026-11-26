"""Parser del protocollo seriale testuale inviato dallo sketch Arduino.

Formato di una riga (terminata da ``\\r\\n`` per via di ``Serial.println``)::

    S1:1.23,S2:0.98,S3:2.10,S4:1.75,S5:0.66

Il parser usa l'etichetta ``Sx`` per posizionare il valore nel canale
corretto, quindi è indipendente dall'ordine dei token.
"""

from __future__ import annotations

import re

import numpy as np

from config import NUM_SENSORS

_TOKEN_RE = re.compile(r"^\s*S(\d+)\s*:\s*([-+]?\d+(?:\.\d+)?)\s*$")


class PacketParseError(ValueError):
    """Sollevata quando una riga seriale è parziale o malformata."""


def parse_line(line: str, num_channels: int = NUM_SENSORS) -> np.ndarray:
    """Converte una riga di testo in un array di ``num_channels`` float.

    Args:
        line: Riga ricevuta (con o senza terminatore).
        num_channels: Numero di canali attesi.

    Returns:
        Array ``float64`` di lunghezza ``num_channels`` (indice 0 = S1).

    Raises:
        PacketParseError: Se la riga è incompleta, contiene token non
            validi, canali duplicati o fuori range.
    """
    stripped = line.strip()
    if not stripped:
        raise PacketParseError("Riga vuota")

    tokens = stripped.split(",")
    if len(tokens) != num_channels:
        raise PacketParseError(
            f"Attesi {num_channels} token, ricevuti {len(tokens)}: {stripped!r}"
        )

    values = np.full(num_channels, np.nan, dtype=np.float64)
    seen: set[int] = set()
    for token in tokens:
        match = _TOKEN_RE.match(token)
        if match is None:
            raise PacketParseError(f"Token non valido: {token!r}")
        index = int(match.group(1)) - 1
        if not 0 <= index < num_channels:
            raise PacketParseError(f"Canale fuori range: {token!r}")
        if index in seen:
            raise PacketParseError(f"Canale duplicato: {token!r}")
        seen.add(index)
        values[index] = float(match.group(2))

    return values
