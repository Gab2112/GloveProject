"""Visualizzatori della mano virtuale.

* :class:`BaseHandVisualizer` definisce l'interfaccia comune
  ``update_fingers(raw_values, deltas, active_states, intensities)``.
* :class:`HandVisualizer2D` è l'implementazione 2D basata su ``QPainter``.

Per il futuro upgrade 3D basterà creare ``HandVisualizer3D`` (es. in
``hand_visualizer_3d.py`` con ``pyqtgraph.opengl`` / VTK / Qt3D) che erediti
da :class:`BaseHandVisualizer`: la ``MainWindow`` non dovrà cambiare.
"""

from __future__ import annotations

from abc import ABCMeta, abstractmethod
from dataclasses import dataclass
from enum import Enum

import numpy as np
from PyQt6.QtCore import QPointF, QRectF, Qt
from PyQt6.QtGui import QColor, QFont, QPainter, QPaintEvent, QPen
from PyQt6.QtWidgets import QSizePolicy, QWidget

from config import FINGER_NAMES, FINGER_PLOT_COLORS, NUM_SENSORS


class _QABCMeta(type(QWidget), ABCMeta):  # type: ignore[misc]
    """Metaclasse che combina quella di Qt (sip) con ``ABCMeta``."""


class ColorMode(Enum):
    """Strategia di colorazione delle dita."""

    THRESHOLD = "threshold"          # grigio / colore acceso (on-off)
    PROPORTIONAL = "proportional"    # sfumatura proporzionale a |Δ|


class BaseHandVisualizer(QWidget, metaclass=_QABCMeta):
    """Interfaccia astratta per qualsiasi rappresentazione della mano."""

    @abstractmethod
    def update_fingers(
        self,
        raw_values: np.ndarray,
        deltas: np.ndarray,
        active_states: np.ndarray,
        intensities: np.ndarray | None = None,
    ) -> None:
        """Aggiorna lo stato visivo delle 5 dita.

        Args:
            raw_values: Valori correnti dei sensori [V].
            deltas: Scostamento dalla baseline [V] con segno.
            active_states: ``True`` se |Δ| supera la soglia.
            intensities: Valori 0..1 proporzionali a |Δ|.
        """

    @abstractmethod
    def reset(self) -> None:
        """Riporta la mano allo stato neutro."""

    @abstractmethod
    def set_color_mode(self, mode: ColorMode) -> None:
        """Imposta la strategia di colorazione."""


# --------------------------------------------------------------------------- #
# Implementazione 2D
# --------------------------------------------------------------------------- #
@dataclass(frozen=True)
class FingerGeometry:
    """Geometria di un dito nel sistema di coordinate logico."""

    base_x: float
    base_y: float
    angle_deg: float   # rotazione oraria rispetto alla verticale
    length: float
    width: float


# Coordinate logiche (la vista viene scalata mantenendo l'aspect ratio).
_LOGICAL_W = 400.0
_LOGICAL_H = 600.0
_PALM_RECT = QRectF(110.0, 230.0, 180.0, 170.0)
_WRIST_RECT = QRectF(140.0, 390.0, 120.0, 70.0)
_FINGERS: tuple[FingerGeometry, ...] = (
    FingerGeometry(125.0, 345.0, -55.0, 105.0, 44.0),  # Pollice
    FingerGeometry(133.0, 245.0, -8.0, 140.0, 40.0),   # Indice
    FingerGeometry(178.0, 238.0, -1.0, 160.0, 41.0),   # Medio
    FingerGeometry(223.0, 242.0, 5.0, 148.0, 39.0),    # Anulare
    FingerGeometry(266.0, 255.0, 13.0, 115.0, 35.0),   # Mignolo
)

_BACKGROUND = QColor("#1e1e1e")
_NEUTRAL_FILL = QColor("#8a8a8a")
_OUTLINE = QColor("#3a3a3a")
_PALM_FILL = QColor("#9a9a9a")
_COLOR_DROP = QColor("#00e676")  # tensione SCENDE (Δ < 0) -> dito illuminato verde
_COLOR_RISE = QColor("#ff1744")  # tensione SALE   (Δ > 0) -> dito rosso
_TEXT = QColor("#e0e0e0")


def _lerp_color(a: QColor, b: QColor, t: float) -> QColor:
    """Interpolazione lineare tra due colori (``t`` in 0..1)."""
    t = float(np.clip(t, 0.0, 1.0))
    return QColor(
        round(a.red() + (b.red() - a.red()) * t),
        round(a.green() + (b.green() - a.green()) * t),
        round(a.blue() + (b.blue() - a.blue()) * t),
    )


class HandVisualizer2D(BaseHandVisualizer):
    """Mano stilizzata 2D disegnata con ``QPainter``."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setMinimumSize(260, 390)
        self.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding
        )
        self._color_mode = ColorMode.THRESHOLD
        self._raw = np.zeros(NUM_SENSORS)
        self._deltas = np.zeros(NUM_SENSORS)
        self._active = np.zeros(NUM_SENSORS, dtype=bool)
        self._intensities = np.zeros(NUM_SENSORS)
        self._has_data = False

    # -- interfaccia BaseHandVisualizer -------------------------------- #
    def update_fingers(
        self,
        raw_values: np.ndarray,
        deltas: np.ndarray,
        active_states: np.ndarray,
        intensities: np.ndarray | None = None,
    ) -> None:
        self._raw = np.asarray(raw_values, dtype=np.float64).copy()
        self._deltas = np.asarray(deltas, dtype=np.float64).copy()
        self._active = np.asarray(active_states, dtype=bool).copy()
        self._intensities = (
            np.asarray(intensities, dtype=np.float64).copy()
            if intensities is not None
            else self._active.astype(np.float64)
        )
        self._has_data = True
        self.update()  # schedula un repaint (non blocca)

    def reset(self) -> None:
        self._raw[:] = 0.0
        self._deltas[:] = 0.0
        self._active[:] = False
        self._intensities[:] = 0.0
        self._has_data = False
        self.update()

    def set_color_mode(self, mode: ColorMode) -> None:
        self._color_mode = mode
        self.update()

    # -- disegno -------------------------------------------------------- #
    def _finger_color(self, index: int) -> QColor:
        """Colore di riempimento del dito ``index`` secondo la modalità."""
        # Il segno di Δ sceglie il colore: calo -> verde, aumento -> rosso.
        target = _COLOR_DROP if self._deltas[index] < 0.0 else _COLOR_RISE
        if self._color_mode is ColorMode.PROPORTIONAL:
            return _lerp_color(_NEUTRAL_FILL, target, self._intensities[index])
        return target if self._active[index] else _NEUTRAL_FILL

    def paintEvent(self, event: QPaintEvent | None) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.fillRect(self.rect(), _BACKGROUND)

        # Scala uniforme e centratura del sistema logico nel widget.
        scale = min(self.width() / _LOGICAL_W, self.height() / _LOGICAL_H)
        offset_x = (self.width() - _LOGICAL_W * scale) / 2.0
        offset_y = (self.height() - _LOGICAL_H * scale) / 2.0
        painter.translate(offset_x, offset_y)
        painter.scale(scale, scale)

        self._draw_wrist(painter)
        for i, geom in enumerate(_FINGERS):
            self._draw_finger(painter, i, geom)
        self._draw_palm(painter)
        self._draw_readout(painter)
        painter.end()

    def _draw_wrist(self, painter: QPainter) -> None:
        painter.setPen(QPen(_OUTLINE, 2))
        painter.setBrush(_PALM_FILL.darker(115))
        painter.drawRoundedRect(_WRIST_RECT, 12, 12)

    def _draw_palm(self, painter: QPainter) -> None:
        painter.setPen(QPen(_OUTLINE, 2))
        painter.setBrush(_PALM_FILL)
        painter.drawRoundedRect(_PALM_RECT, 30, 30)

        painter.setPen(QColor("#202020"))
        font = QFont(self.font())
        font.setPointSizeF(9.0)
        painter.setFont(font)
        message = "In attesa di dati..." if not self._has_data else "Palmo"
        painter.drawText(_PALM_RECT, Qt.AlignmentFlag.AlignCenter, message)

    def _draw_finger(
        self, painter: QPainter, index: int, geom: FingerGeometry
    ) -> None:
        painter.save()
        painter.translate(QPointF(geom.base_x, geom.base_y))
        painter.rotate(geom.angle_deg)

        fill = self._finger_color(index)
        active = bool(self._active[index])
        outline = fill.lighter(150) if active else _OUTLINE
        painter.setPen(QPen(outline, 4 if active else 2))
        painter.setBrush(fill)

        # Il dito si estende di 25 px dentro il palmo (coperto dal palmo).
        body = QRectF(-geom.width / 2, -geom.length, geom.width,
                      geom.length + 25.0)
        radius = geom.width / 2
        painter.drawRoundedRect(body, radius, radius)

        # Pieghe delle falangi.
        painter.setPen(QPen(fill.darker(140), 1.5))
        for frac in (0.33, 0.62):
            y = -geom.length * frac
            painter.drawLine(QPointF(-geom.width * 0.3, y),
                             QPointF(geom.width * 0.3, y))

        # Nome del dito sopra la punta.
        font = QFont(self.font())
        font.setPointSizeF(8.5)
        font.setBold(active)
        painter.setFont(font)
        painter.setPen(_TEXT)
        painter.drawText(
            QRectF(-45.0, -geom.length - 22.0, 90.0, 18.0),
            Qt.AlignmentFlag.AlignCenter,
            FINGER_NAMES[index],
        )
        painter.restore()

    def _draw_readout(self, painter: QPainter) -> None:
        """Tabella numerica valore grezzo / Δ sotto la mano."""
        font = QFont("Consolas")
        font.setStyleHint(QFont.StyleHint.Monospace)
        font.setPointSizeF(8.5)
        painter.setFont(font)
        top = 478.0
        row_h = 23.0
        for i in range(NUM_SENSORS):
            y = top + i * row_h
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(QColor(FINGER_PLOT_COLORS[i]))
            painter.drawRect(QRectF(40.0, y + 5.0, 12.0, 12.0))
            painter.setBrush(self._finger_color(i))
            painter.drawEllipse(QRectF(345.0, y + 4.0, 14.0, 14.0))
            painter.setPen(_TEXT)
            text = (
                f"{FINGER_NAMES[i]:<8} {self._raw[i]:5.2f} V  "
                f"Δ {self._deltas[i]:+5.2f} V"
            )
            painter.drawText(
                QRectF(60.0, y, 280.0, row_h),
                Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft,
                text,
            )
