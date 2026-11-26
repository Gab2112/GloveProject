"""Elaborazione del segnale e rilevamento della variazione rispetto al riposo.

Versione attuale: **nessun filtro** (pass-through). Il punto di innesto per i
filtri futuri è la catena ``SignalProcessor._filters``: basterà creare una
sottoclasse di :class:`BaseFilter` (es. ``MovingAverageFilter``,
``ButterworthLowPass``) e aggiungerla con :meth:`SignalProcessor.add_filter`.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from config import DEFAULT_FULL_SCALE_V, DEFAULT_THRESHOLD_V, NUM_SENSORS


# --------------------------------------------------------------------------- #
# Filtri
# --------------------------------------------------------------------------- #
class BaseFilter(ABC):
    """Interfaccia comune per qualsiasi filtro multicanale."""

    @abstractmethod
    def process(self, values: np.ndarray, timestamp: float) -> np.ndarray:
        """Elabora un campione multicanale e restituisce il risultato."""

    @abstractmethod
    def reset(self) -> None:
        """Azzera lo stato interno del filtro (es. alla riconnessione)."""


class PassThroughFilter(BaseFilter):
    """Filtro identità: restituisce il dato grezzo invariato."""

    def process(self, values: np.ndarray, timestamp: float) -> np.ndarray:
        return np.asarray(values, dtype=np.float64).copy()

    def reset(self) -> None:
        # Filtro senza stato: non c'è nulla da azzerare.
        return None


class SignalProcessor:
    """Catena di filtri applicata in sequenza a ogni campione.

    Di default contiene solo un :class:`PassThroughFilter`, quindi l'uscita
    coincide esattamente con il segnale grezzo ricevuto da Arduino.
    """

    def __init__(self, filters: Sequence[BaseFilter] | None = None) -> None:
        self._filters: list[BaseFilter] = (
            list(filters) if filters else [PassThroughFilter()]
        )

    @property
    def filters(self) -> tuple[BaseFilter, ...]:
        """Filtri attualmente in catena (sola lettura)."""
        return tuple(self._filters)

    def add_filter(self, flt: BaseFilter) -> None:
        """Aggiunge un filtro in coda alla catena."""
        self._filters.append(flt)

    def clear_filters(self) -> None:
        """Ripristina la configurazione pass-through."""
        self._filters = [PassThroughFilter()]

    def reset(self) -> None:
        """Azzera lo stato di tutti i filtri."""
        for flt in self._filters:
            flt.reset()

    def process(self, values: np.ndarray, timestamp: float) -> np.ndarray:
        """Applica la catena di filtri al campione."""
        out = np.asarray(values, dtype=np.float64)
        for flt in self._filters:
            out = flt.process(out, timestamp)
        return out


# --------------------------------------------------------------------------- #
# Rilevamento variazione
# --------------------------------------------------------------------------- #
@dataclass(frozen=True)
class ChangeState:
    """Risultato del confronto con la baseline per tutti i canali."""

    deltas: np.ndarray        # valore - baseline [V], con segno
    active: np.ndarray        # bool: |delta| >= soglia
    intensities: np.ndarray   # 0..1: |delta| / fondo scala (saturato)


class ChangeDetector:
    """Rileva variazioni di tensione (cali e aumenti) rispetto al riposo."""

    def __init__(
        self,
        num_channels: int = NUM_SENSORS,
        threshold: float = DEFAULT_THRESHOLD_V,
        full_scale: float = DEFAULT_FULL_SCALE_V,
    ) -> None:
        self._num_channels = num_channels
        self._baseline: np.ndarray | None = None
        self.threshold = threshold
        self.full_scale = full_scale

    # -- proprietà ------------------------------------------------------ #
    @property
    def baseline(self) -> np.ndarray | None:
        """Copia della baseline corrente (``None`` se non impostata)."""
        return None if self._baseline is None else self._baseline.copy()

    @property
    def has_baseline(self) -> bool:
        """``True`` se è stata impostata una baseline."""
        return self._baseline is not None

    @property
    def threshold(self) -> float:
        """Variazione minima |Δ| per attivare un canale, in Volt."""
        return self._threshold

    @threshold.setter
    def threshold(self, value: float) -> None:
        self._threshold = max(float(value), 1e-6)

    @property
    def full_scale(self) -> float:
        """|Δ| [V] corrispondente all'intensità colore massima."""
        return self._full_scale

    @full_scale.setter
    def full_scale(self, value: float) -> None:
        self._full_scale = max(float(value), 1e-6)

    # -- operazioni ----------------------------------------------------- #
    def set_baseline(self, values: np.ndarray) -> None:
        """Salva ``values`` come condizione di riposo."""
        arr = np.asarray(values, dtype=np.float64)
        if arr.shape != (self._num_channels,):
            raise ValueError(
                f"Baseline con forma {arr.shape}, attesa ({self._num_channels},)"
            )
        self._baseline = arr.copy()

    def clear_baseline(self) -> None:
        """Rimuove la baseline (nessun dito risulterà attivo)."""
        self._baseline = None

    def evaluate(self, values: np.ndarray) -> ChangeState:
        """Calcola delta, stato attivo e intensità per ogni canale."""
        arr = np.asarray(values, dtype=np.float64)
        if self._baseline is None:
            zeros = np.zeros(self._num_channels, dtype=np.float64)
            return ChangeState(
                deltas=zeros,
                active=np.zeros(self._num_channels, dtype=bool),
                intensities=zeros.copy(),
            )
        deltas = arr - self._baseline
        # Si usa il valore assoluto: sia i cali sia gli aumenti di tensione
        # attivano il dito (il colore, verde o rosso, dipende dal segno).
        magnitude = np.abs(deltas)
        # Piccola tolleranza per evitare problemi di arrotondamento float
        # (i dati arrivano quantizzati a 0.01 V).
        active = magnitude >= (self._threshold - 1e-9)
        intensities = np.clip(magnitude / self._full_scale, 0.0, 1.0)
        return ChangeState(deltas=deltas, active=active, intensities=intensities)
