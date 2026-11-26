"""Configurazione centralizzata dell'applicazione guanto sensorizzato.

Tutte le costanti di protocollo, GUI e rilevamento sono raccolte qui per
evitare "numeri magici" sparsi nei moduli.
"""

from __future__ import annotations

from typing import Final

# --------------------------------------------------------------------------- #
# Sensori / dita
# --------------------------------------------------------------------------- #
NUM_SENSORS: Final[int] = 5

#: Etichette dei canali così come trasmesse dallo sketch Arduino.
SENSOR_LABELS: Final[tuple[str, ...]] = ("S1", "S2", "S3", "S4", "S5")

#: Mappatura canale -> dito (S1 = pollice ... S5 = mignolo).
FINGER_NAMES: Final[tuple[str, ...]] = (
    "Pollice",
    "Indice",
    "Medio",
    "Anulare",
    "Mignolo",
)

#: Pin analogici Arduino corrispondenti (solo informativo).
ARDUINO_PINS: Final[tuple[str, ...]] = ("A1", "A2", "A3", "A4", "A6")

#: Colori delle curve nel grafico (uno per dito).
FINGER_PLOT_COLORS: Final[tuple[str, ...]] = (
    "#e6194b",  # Pollice  - rosso
    "#f58231",  # Indice   - arancio
    "#ffe119",  # Medio    - giallo
    "#3cb44b",  # Anulare  - verde
    "#4363d8",  # Mignolo  - blu
)

# --------------------------------------------------------------------------- #
# Protocollo seriale (dedotto dallo sketch Arduino)
# --------------------------------------------------------------------------- #
DEFAULT_BAUDRATE: Final[int] = 115200
AVAILABLE_BAUDRATES: Final[tuple[int, ...]] = (
    9600, 19200, 38400, 57600, 115200, 230400,
)
#: Timeout di lettura: permette al thread di controllare il flag di stop.
SERIAL_READ_TIMEOUT_S: Final[float] = 0.1
#: Oltre questa lunghezza un buffer senza '\n' è considerato spazzatura.
MAX_LINE_LENGTH: Final[int] = 512
#: Range nominale delle tensioni calcolate dallo sketch (0 - 5 V).
VOLTAGE_MIN: Final[float] = 0.0
VOLTAGE_MAX: Final[float] = 5.0

# --------------------------------------------------------------------------- #
# Buffer e grafici
# --------------------------------------------------------------------------- #
PLOT_WINDOW_S: Final[float] = 10.0
#: Capacità del ring buffer: ampia per supportare frequenze future più alte.
BUFFER_CAPACITY: Final[int] = 20_000
#: Periodo di refresh della GUI (~30 FPS).
GUI_REFRESH_MS: Final[int] = 33
#: Se non arrivano campioni per questo intervallo, viene mostrato un avviso.
DATA_WATCHDOG_S: Final[float] = 2.0

# --------------------------------------------------------------------------- #
# Viste
# --------------------------------------------------------------------------- #
#: ``True`` = mostra la mano virtuale a destra; ``False`` = solo grafici.
ENABLE_HAND_VIEW: Final[bool] = True

# --------------------------------------------------------------------------- #
# Rilevamento variazione
# --------------------------------------------------------------------------- #
DEFAULT_THRESHOLD_V: Final[float] = -0.10
MIN_THRESHOLD_V: Final[float] = 0.01   # = risoluzione di stampa (2 decimali)
MAX_THRESHOLD_V: Final[float] = 2.00
DEFAULT_FULL_SCALE_V: Final[float] = 0.50
