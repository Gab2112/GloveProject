"""Punto di ingresso dell'applicazione guanto sensorizzato.

Esecuzione::

    python main.py
"""

from __future__ import annotations

import sys

# PyQt6 va importato prima di pyqtgraph, così pyqtgraph usa questo binding.
from PyQt6.QtWidgets import QApplication

import pyqtgraph as pg

from main_window import MainWindow


def main() -> int:
    """Crea l'applicazione Qt e avvia l'event loop."""
    pg.setConfigOptions(antialias=True, foreground="#d0d0d0")
    app = QApplication(sys.argv)
    app.setApplicationName("Glove DAQ")
    app.setStyle("Fusion")

    window = MainWindow()
    window.resize(1400, 820)
    window.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
