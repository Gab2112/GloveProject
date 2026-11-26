"""Widget PyQtGraph per i 5 segnali grezzi con finestra temporale scorrevole."""

from __future__ import annotations

import numpy as np
import pyqtgraph as pg
from PyQt6.QtWidgets import QWidget

from config import (
    FINGER_NAMES,
    FINGER_PLOT_COLORS,
    NUM_SENSORS,
    PLOT_WINDOW_S,
    SENSOR_LABELS,
    VOLTAGE_MAX,
    VOLTAGE_MIN,
)


class RealTimePlotWidget(pg.PlotWidget):
    """Grafico multicanale: asse X = secondi relativi all'istante attuale."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent=parent)
        self._window_s = PLOT_WINDOW_S

        self.setBackground("#1e1e1e")
        item = self.getPlotItem()
        item.showGrid(x=True, y=True, alpha=0.3)
        item.setLabel("left", "Tensione", units="V")
        item.setLabel("bottom", "Tempo", units="s")
        item.getAxis("left").enableAutoSIPrefix(False)
        item.getAxis("bottom").enableAutoSIPrefix(False)
        item.setTitle("Segnali grezzi dei sensori di strain")
        item.setMouseEnabled(x=False, y=True)
        item.setClipToView(True)
        item.setXRange(-self._window_s, 0.0, padding=0.0)
        self.addLegend(offset=(10, 10))

        self._curves: list[pg.PlotDataItem] = []
        for i in range(NUM_SENSORS):
            curve = self.plot(
                [],
                [],
                pen=pg.mkPen(FINGER_PLOT_COLORS[i], width=2),
                name=f"{SENSOR_LABELS[i]} - {FINGER_NAMES[i]}",
            )
            self._curves.append(curve)

        self.set_auto_range_y(True)

    @property
    def window_s(self) -> float:
        """Ampiezza della finestra temporale visualizzata [s]."""
        return self._window_s

    def set_window(self, seconds: float) -> None:
        """Modifica la finestra temporale scorrevole."""
        self._window_s = max(float(seconds), 0.5)
        self.getPlotItem().setXRange(-self._window_s, 0.0, padding=0.0)

    def set_auto_range_y(self, enabled: bool) -> None:
        """Auto-scala Y oppure range fisso 0-5 V."""
        item = self.getPlotItem()
        if enabled:
            item.enableAutoRange(axis="y", enable=True)
        else:
            item.disableAutoRange(axis="y")
            item.setYRange(VOLTAGE_MIN, VOLTAGE_MAX, padding=0.02)

    def update_data(
        self, timestamps: np.ndarray, data: np.ndarray, reference_time: float
    ) -> None:
        """Ridisegna le curve; X = ``timestamps - reference_time``."""
        x = timestamps - reference_time
        for i, curve in enumerate(self._curves):
            curve.setData(x, data[:, i])

    def clear_data(self) -> None:
        """Svuota tutte le curve."""
        for curve in self._curves:
            curve.setData([], [])
