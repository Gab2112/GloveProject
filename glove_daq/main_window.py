"""Finestra principale: orchestrazione di acquisizione, elaborazione e viste.

Flusso dati::

    SerialWorker (QThread) --sample_received--> MainWindow._on_sample
        -> SignalProcessor.process  (pass-through)
        -> TimeSeriesBuffer.append
    QTimer (~30 FPS) -> RealTimePlotWidget.update_data
                     -> ChangeDetector.evaluate -> BaseHandVisualizer.update_fingers
"""

from __future__ import annotations

import time
from enum import Enum, auto

import numpy as np
from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QCloseEvent
from PyQt6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDoubleSpinBox,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QSlider,
    QSplitter,
    QVBoxLayout,
    QWidget,
)
from serial.tools import list_ports

from config import (
    AVAILABLE_BAUDRATES,
    BUFFER_CAPACITY,
    DATA_WATCHDOG_S,
    DEFAULT_BAUDRATE,
    DEFAULT_FULL_SCALE_V,
    DEFAULT_THRESHOLD_V,
    ENABLE_HAND_VIEW,
    FINGER_NAMES,
    GUI_REFRESH_MS,
    MAX_THRESHOLD_V,
    MIN_THRESHOLD_V,
    NUM_SENSORS,
    PLOT_WINDOW_S,
)
from data_buffer import TimeSeriesBuffer
from hand_visualizer import BaseHandVisualizer, ColorMode, HandVisualizer2D
from plot_widget import RealTimePlotWidget
from serial_worker import SerialWorker
from signal_processor import ChangeDetector, SignalProcessor

_ARDUINO_USB_VID = 0x2341
_SLIDER_SCALE = 100  # slider intero: 1 tick = 0.01 V


class ConnectionState(Enum):
    """Stati della connessione seriale."""

    DISCONNECTED = auto()
    CONNECTING = auto()
    CONNECTED = auto()


class MainWindow(QMainWindow):
    """Finestra principale con layout split-screen grafici | mano."""

    def __init__(
        self,
        hand_visualizer: BaseHandVisualizer | None = None,
        processor: SignalProcessor | None = None,
    ) -> None:
        super().__init__()
        self.setWindowTitle("Guanto Sensorizzato - Monitor Real-Time")

        # Componenti di dominio (iniettabili per estensioni future).
        self._processor = processor or SignalProcessor()
        self._detector = ChangeDetector(
            NUM_SENSORS, DEFAULT_THRESHOLD_V, DEFAULT_FULL_SCALE_V
        )
        self._buffer = TimeSeriesBuffer(BUFFER_CAPACITY, NUM_SENSORS)
        self._hand: BaseHandVisualizer = hand_visualizer or HandVisualizer2D()

        # Stato runtime.
        self._worker: SerialWorker | None = None
        self._state = ConnectionState.DISCONNECTED
        self._latest_raw: np.ndarray | None = None
        self._latest_processed: np.ndarray | None = None
        self._last_sample_time: float | None = None
        self._connect_time: float = 0.0
        self._freeze_time: float | None = None
        self._rate_count = 0
        self._rate_t0 = time.perf_counter()
        self._measured_rate = 0.0

        self._build_ui()
        self._connect_ui_signals()
        self.refresh_ports()
        self._set_state(ConnectionState.DISCONNECTED)

        self._timer = QTimer(self)
        self._timer.setTimerType(Qt.TimerType.PreciseTimer)
        self._timer.timeout.connect(self._on_refresh)
        self._timer.start(GUI_REFRESH_MS)

    # ================================================================== #
    # Costruzione UI
    # ================================================================== #
    def _build_ui(self) -> None:
        central = QWidget(self)
        root = QVBoxLayout(central)
        root.addLayout(self._build_connection_bar())

        splitter = QSplitter(Qt.Orientation.Horizontal, central)
        splitter.addWidget(self._build_plot_panel())
        self._hand_panel = self._build_hand_panel()
        splitter.addWidget(self._hand_panel)
        splitter.setStretchFactor(0, 3)
        splitter.setStretchFactor(1, 2)
        splitter.setSizes([850, 500])
        # Pannello mano (e controlli di rilevamento) nascosto se disabilitato.
        self._hand_panel.setVisible(ENABLE_HAND_VIEW)
        root.addWidget(splitter, stretch=1)
        self.setCentralWidget(central)

        self._rate_label = QLabel("Frequenza: -- Hz")
        self._packets_label = QLabel("Pacchetti OK: 0 | Scartati: 0")
        self.statusBar().addPermanentWidget(self._rate_label)
        self.statusBar().addPermanentWidget(self._packets_label)

    def _build_connection_bar(self) -> QHBoxLayout:
        bar = QHBoxLayout()
        self._port_combo = QComboBox()
        self._port_combo.setMinimumWidth(280)
        self._refresh_btn = QPushButton("Aggiorna porte")
        self._baud_combo = QComboBox()
        for baud in AVAILABLE_BAUDRATES:
            self._baud_combo.addItem(str(baud), baud)
        self._baud_combo.setCurrentIndex(
            AVAILABLE_BAUDRATES.index(DEFAULT_BAUDRATE)
        )
        self._connect_btn = QPushButton("Connetti")
        self._disconnect_btn = QPushButton("Disconnetti")
        self._conn_indicator = QLabel()
        self._conn_indicator.setMinimumWidth(220)

        bar.addWidget(QLabel("Porta:"))
        bar.addWidget(self._port_combo)
        bar.addWidget(self._refresh_btn)
        bar.addSpacing(12)
        bar.addWidget(QLabel("Baud:"))
        bar.addWidget(self._baud_combo)
        bar.addSpacing(12)
        bar.addWidget(self._connect_btn)
        bar.addWidget(self._disconnect_btn)
        bar.addStretch(1)
        bar.addWidget(self._conn_indicator)
        return bar

    def _build_plot_panel(self) -> QWidget:
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(0, 0, 0, 0)
        self._plot = RealTimePlotWidget(panel)
        layout.addWidget(self._plot, stretch=1)

        options = QHBoxLayout()
        self._autoscale_chk = QCheckBox("Auto-scala Y")
        self._autoscale_chk.setChecked(True)
        self._window_spin = QDoubleSpinBox()
        self._window_spin.setRange(2.0, 60.0)
        self._window_spin.setSingleStep(1.0)
        self._window_spin.setDecimals(0)
        self._window_spin.setSuffix(" s")
        self._window_spin.setValue(PLOT_WINDOW_S)
        self._clear_plot_btn = QPushButton("Pulisci grafico")
        options.addWidget(self._autoscale_chk)
        options.addSpacing(12)
        options.addWidget(QLabel("Finestra:"))
        options.addWidget(self._window_spin)
        options.addStretch(1)
        options.addWidget(self._clear_plot_btn)
        layout.addLayout(options)
        return panel

    def _build_hand_panel(self) -> QWidget:
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self._hand, stretch=1)

        group = QGroupBox("Rilevamento movimento")
        grid = QGridLayout(group)

        self._baseline_btn = QPushButton("Imposta Riposo (Baseline)")
        self._baseline_btn.setStyleSheet("font-weight: bold;")
        self._clear_baseline_btn = QPushButton("Rimuovi baseline")
        grid.addWidget(self._baseline_btn, 0, 0, 1, 2)
        grid.addWidget(self._clear_baseline_btn, 0, 2)

        self._threshold_slider = QSlider(Qt.Orientation.Horizontal)
        self._threshold_slider.setRange(
            round(MIN_THRESHOLD_V * _SLIDER_SCALE),
            round(MAX_THRESHOLD_V * _SLIDER_SCALE),
        )
        self._threshold_slider.setValue(round(DEFAULT_THRESHOLD_V * _SLIDER_SCALE))
        self._threshold_spin = QDoubleSpinBox()
        self._threshold_spin.setRange(MIN_THRESHOLD_V, MAX_THRESHOLD_V)
        self._threshold_spin.setSingleStep(0.01)
        self._threshold_spin.setDecimals(2)
        self._threshold_spin.setSuffix(" V")
        self._threshold_spin.setValue(DEFAULT_THRESHOLD_V)
        grid.addWidget(QLabel("Soglia Δ:"), 1, 0)
        grid.addWidget(self._threshold_slider, 1, 1)
        grid.addWidget(self._threshold_spin, 1, 2)

        self._mode_combo = QComboBox()
        self._mode_combo.addItem("Soglia (on/off)", ColorMode.THRESHOLD)
        self._mode_combo.addItem("Proporzionale a |Δ|", ColorMode.PROPORTIONAL)
        grid.addWidget(QLabel("Colore:"), 2, 0)
        grid.addWidget(self._mode_combo, 2, 1, 1, 2)

        self._full_scale_spin = QDoubleSpinBox()
        self._full_scale_spin.setRange(0.02, 5.0)
        self._full_scale_spin.setSingleStep(0.05)
        self._full_scale_spin.setDecimals(2)
        self._full_scale_spin.setSuffix(" V")
        self._full_scale_spin.setValue(DEFAULT_FULL_SCALE_V)
        self._full_scale_spin.setEnabled(False)
        grid.addWidget(QLabel("Fondo scala |Δ|:"), 3, 0)
        grid.addWidget(self._full_scale_spin, 3, 1, 1, 2)

        self._baseline_label = QLabel()
        self._baseline_label.setStyleSheet("font-family: Consolas, monospace;")
        self._baseline_label.setWordWrap(True)
        grid.addWidget(self._baseline_label, 4, 0, 1, 3)
        self._update_baseline_label()

        layout.addWidget(group)
        return panel

    def _connect_ui_signals(self) -> None:
        self._refresh_btn.clicked.connect(self.refresh_ports)
        self._connect_btn.clicked.connect(self.connect_serial)
        self._disconnect_btn.clicked.connect(self.disconnect_serial)
        self._autoscale_chk.toggled.connect(self._plot.set_auto_range_y)
        self._window_spin.valueChanged.connect(self._plot.set_window)
        self._clear_plot_btn.clicked.connect(self._on_clear_plot)
        self._baseline_btn.clicked.connect(self._on_set_baseline)
        self._clear_baseline_btn.clicked.connect(self._on_clear_baseline)
        self._threshold_slider.valueChanged.connect(self._on_slider_changed)
        self._threshold_spin.valueChanged.connect(self._on_threshold_spin_changed)
        self._mode_combo.currentIndexChanged.connect(self._on_mode_changed)
        self._full_scale_spin.valueChanged.connect(self._on_full_scale_changed)

    # ================================================================== #
    # Gestione porte / connessione
    # ================================================================== #
    def refresh_ports(self) -> None:
        """Ricarica l'elenco delle porte seriali disponibili."""
        previous = self._port_combo.currentData()
        self._port_combo.clear()
        ports = sorted(list_ports.comports(), key=lambda p: p.device)

        if not ports:
            self._port_combo.addItem("Nessuna porta trovata", None)
            self._connect_btn.setEnabled(False)
            return

        preferred_index = 0
        for i, info in enumerate(ports):
            label = f"{info.device} - {info.description}"
            self._port_combo.addItem(label, info.device)
            is_arduino = (
                info.vid == _ARDUINO_USB_VID
                or "arduino" in (info.description or "").lower()
            )
            if is_arduino:
                preferred_index = i
        for i, info in enumerate(ports):
            if info.device == previous:
                preferred_index = i
        self._port_combo.setCurrentIndex(preferred_index)
        self._connect_btn.setEnabled(self._state is ConnectionState.DISCONNECTED)
        self.statusBar().showMessage(f"Trovate {len(ports)} porte seriali", 3000)

    def connect_serial(self) -> None:
        """Avvia il thread di acquisizione sulla porta selezionata."""
        if self._worker is not None:
            return
        port = self._port_combo.currentData()
        if not port:
            QMessageBox.warning(self, "Porta", "Seleziona una porta seriale valida.")
            return
        baud = int(self._baud_combo.currentData())

        worker = SerialWorker(port, baud, NUM_SENSORS, self)
        worker.connected.connect(self._on_connected)
        worker.sample_received.connect(self._on_sample)
        worker.connection_lost.connect(self._on_connection_lost)
        worker.status_message.connect(self._on_status_message)
        worker.finished.connect(self._on_worker_finished)
        self._worker = worker
        self._set_state(ConnectionState.CONNECTING)
        worker.start()

    def disconnect_serial(self) -> None:
        """Arresta il thread di acquisizione (chiusura pulita della porta)."""
        if self._worker is None:
            return
        self._worker.stop()
        self.statusBar().showMessage("Disconnesso", 3000)

    def _on_connected(self, port: str) -> None:
        self._processor.reset()
        self._buffer.clear()
        self._plot.clear_data()
        self._hand.reset()
        self._detector.clear_baseline()
        self._update_baseline_label()
        self._latest_raw = None
        self._latest_processed = None
        self._last_sample_time = None
        self._freeze_time = None
        self._connect_time = time.perf_counter()
        self._rate_count = 0
        self._rate_t0 = self._connect_time
        self._set_state(ConnectionState.CONNECTED)

    def _on_status_message(self, message: str) -> None:
        self.statusBar().showMessage(message, 4000)

    def _on_connection_lost(self, message: str) -> None:
        self.statusBar().showMessage(message, 8000)
        QMessageBox.warning(self, "Errore seriale", message)

    def _on_worker_finished(self) -> None:
        worker = self.sender()
        if worker is not self._worker or self._worker is None:
            return
        self._worker.deleteLater()
        self._worker = None
        self._freeze_time = self._last_sample_time or time.perf_counter()
        self._set_state(ConnectionState.DISCONNECTED)

    def _set_state(self, state: ConnectionState) -> None:
        """Aggiorna abilitazione dei controlli e indicatore di stato."""
        self._state = state
        disconnected = state is ConnectionState.DISCONNECTED
        has_port = self._port_combo.currentData() is not None
        self._connect_btn.setEnabled(disconnected and has_port)
        self._disconnect_btn.setEnabled(not disconnected)
        self._port_combo.setEnabled(disconnected)
        self._baud_combo.setEnabled(disconnected)
        self._refresh_btn.setEnabled(disconnected)
        styles = {
            ConnectionState.DISCONNECTED: ("● Disconnesso", "#9e9e9e"),
            ConnectionState.CONNECTING: ("● Connessione...", "#ffb300"),
            ConnectionState.CONNECTED: ("● Connesso", "#00c853"),
        }
        text, color = styles[state]
        self._set_indicator(text, color)

    def _set_indicator(self, text: str, color: str) -> None:
        self._conn_indicator.setText(text)
        self._conn_indicator.setStyleSheet(f"color: {color}; font-weight: bold;")

    # ================================================================== #
    # Dati
    # ================================================================== #
    def _on_sample(self, timestamp: float, values: object) -> None:
        """Riceve un campione grezzo dal thread seriale (nel thread GUI)."""
        raw = np.asarray(values, dtype=np.float64)
        processed = self._processor.process(raw, timestamp)
        self._buffer.append(timestamp, processed)
        self._latest_raw = raw
        self._latest_processed = processed
        self._last_sample_time = timestamp
        self._rate_count += 1

        if ENABLE_HAND_VIEW and not self._detector.has_baseline:
            # Baseline automatica al primo campione valido; l'utente può
            # reimpostarla con il pulsante a mano rilassata.
            self._detector.set_baseline(processed)
            self._update_baseline_label()
            self.statusBar().showMessage(
                "Baseline automatica impostata sul primo campione. "
                "Rilassa la mano e premi 'Imposta Riposo' per ricalibrare.",
                6000,
            )

    def _on_refresh(self) -> None:
        """Tick a ~30 FPS: aggiorna grafico, mano e diagnostica."""
        now = time.perf_counter()
        connected = self._state is ConnectionState.CONNECTED
        reference = now if connected or self._freeze_time is None else self._freeze_time

        t, data = self._buffer.get_window(self._plot.window_s, reference)
        if t.size:
            self._plot.update_data(t, data, reference)

        if (
            ENABLE_HAND_VIEW
            and self._latest_processed is not None
            and self._latest_raw is not None
        ):
            state = self._detector.evaluate(self._latest_processed)
            self._hand.update_fingers(
                self._latest_raw, state.deltas, state.active, state.intensities
            )

        self._update_diagnostics(now, connected)

    def _update_diagnostics(self, now: float, connected: bool) -> None:
        elapsed = now - self._rate_t0
        if elapsed >= 1.0:
            self._measured_rate = self._rate_count / elapsed
            self._rate_count = 0
            self._rate_t0 = now
        if connected:
            self._rate_label.setText(f"Frequenza: {self._measured_rate:5.1f} Hz")
        else:
            self._rate_label.setText("Frequenza: -- Hz")

        if self._worker is not None:
            self._packets_label.setText(
                f"Pacchetti OK: {self._worker.valid_packets} | "
                f"Scartati: {self._worker.bad_packets}"
            )

        if not connected:
            return
        if self._last_sample_time is None:
            if now - self._connect_time > DATA_WATCHDOG_S:
                self._set_indicator(
                    "⚠ Connesso, nessun pacchetto valido (baud?)", "#ff9100"
                )
        elif now - self._last_sample_time > DATA_WATCHDOG_S:
            self._set_indicator("⚠ Nessun dato in arrivo", "#ff9100")
        else:
            self._set_indicator("● Connesso - ricezione dati", "#00c853")

    # ================================================================== #
    # Baseline / soglia / colore
    # ================================================================== #
    def _on_set_baseline(self) -> None:
        if self._latest_processed is None:
            self.statusBar().showMessage(
                "Nessun dato disponibile: connetti il guanto prima.", 4000
            )
            return
        self._detector.set_baseline(self._latest_processed)
        self._update_baseline_label()
        self.statusBar().showMessage("Baseline di riposo aggiornata", 3000)

    def _on_clear_baseline(self) -> None:
        self._detector.clear_baseline()
        self._update_baseline_label()
        self.statusBar().showMessage(
            "Baseline rimossa: verrà reimpostata al prossimo campione", 4000
        )

    def _update_baseline_label(self) -> None:
        baseline = self._detector.baseline
        if baseline is None:
            self._baseline_label.setText("Baseline: non impostata")
            return
        parts = [f"{name[:3]} {val:.2f}" for name, val in zip(FINGER_NAMES, baseline)]
        self._baseline_label.setText("Baseline [V]: " + " | ".join(parts))

    def _on_slider_changed(self, value: int) -> None:
        threshold = value / _SLIDER_SCALE
        self._threshold_spin.blockSignals(True)
        self._threshold_spin.setValue(threshold)
        self._threshold_spin.blockSignals(False)
        self._detector.threshold = threshold

    def _on_threshold_spin_changed(self, value: float) -> None:
        self._threshold_slider.blockSignals(True)
        self._threshold_slider.setValue(round(value * _SLIDER_SCALE))
        self._threshold_slider.blockSignals(False)
        self._detector.threshold = value

    def _on_mode_changed(self, _index: int) -> None:
        mode = self._mode_combo.currentData()
        if isinstance(mode, ColorMode):
            self._hand.set_color_mode(mode)
            self._full_scale_spin.setEnabled(mode is ColorMode.PROPORTIONAL)

    def _on_full_scale_changed(self, value: float) -> None:
        self._detector.full_scale = value

    def _on_clear_plot(self) -> None:
        self._buffer.clear()
        self._plot.clear_data()

    # ================================================================== #
    # Chiusura
    # ================================================================== #
    def closeEvent(self, event: QCloseEvent | None) -> None:  # noqa: N802
        """Arresta timer e thread prima di chiudere la finestra."""
        self._timer.stop()
        if self._worker is not None:
            self._worker.stop()
        if event is not None:
            event.accept()
