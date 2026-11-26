"""Ring buffer numpy per serie temporali multicanale (O(1) in append)."""

from __future__ import annotations

import numpy as np


class TimeSeriesBuffer:
    """Buffer circolare a capacità fissa di campioni ``(t, values[n])``."""

    def __init__(self, capacity: int, num_channels: int) -> None:
        if capacity <= 0:
            raise ValueError("La capacità deve essere positiva")
        self._capacity = capacity
        self._num_channels = num_channels
        self._t = np.zeros(capacity, dtype=np.float64)
        self._data = np.zeros((capacity, num_channels), dtype=np.float64)
        self._write_idx = 0
        self._count = 0

    def __len__(self) -> int:
        return self._count

    @property
    def last_timestamp(self) -> float | None:
        """Timestamp dell'ultimo campione inserito."""
        if self._count == 0:
            return None
        return float(self._t[(self._write_idx - 1) % self._capacity])

    def append(self, timestamp: float, values: np.ndarray) -> None:
        """Inserisce un campione, sovrascrivendo il più vecchio se pieno."""
        self._t[self._write_idx] = timestamp
        self._data[self._write_idx, :] = values
        self._write_idx = (self._write_idx + 1) % self._capacity
        self._count = min(self._count + 1, self._capacity)

    def clear(self) -> None:
        """Svuota il buffer."""
        self._write_idx = 0
        self._count = 0

    def get_ordered(self) -> tuple[np.ndarray, np.ndarray]:
        """Restituisce ``(t, data)`` in ordine cronologico."""
        if self._count < self._capacity:
            return self._t[: self._count], self._data[: self._count]
        idx = self._write_idx
        t = np.concatenate((self._t[idx:], self._t[:idx]))
        data = np.concatenate((self._data[idx:], self._data[:idx]), axis=0)
        return t, data

    def get_window(
        self, window_s: float, reference_time: float
    ) -> tuple[np.ndarray, np.ndarray]:
        """Campioni con ``t >= reference_time - window_s``."""
        t, data = self.get_ordered()
        if t.size == 0:
            return t, data
        start = int(np.searchsorted(t, reference_time - window_s, side="left"))
        return t[start:], data[start:]
