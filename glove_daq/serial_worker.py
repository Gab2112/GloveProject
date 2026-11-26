"""Acquisizione seriale in un thread dedicato (``QThread``).

Il worker legge i byte grezzi dalla porta, ricompone le righe complete in un
buffer interno (così un pacchetto spezzato tra due letture non viene mai
interpretato a metà), effettua il parsing e invia i campioni alla GUI tramite
segnali Qt (thread-safe, connessione *queued*).
"""

from __future__ import annotations

import threading
import time

import serial
from PyQt6.QtCore import QObject, QThread, pyqtSignal

from config import (
    DEFAULT_BAUDRATE,
    MAX_LINE_LENGTH,
    NUM_SENSORS,
    SERIAL_READ_TIMEOUT_S,
)
from protocol import PacketParseError, parse_line


class SerialWorker(QThread):
    """Thread di lettura della porta seriale.

    Signals:
        connected(str): Porta aperta con successo.
        sample_received(float, object): ``(timestamp_perf_counter, ndarray)``.
        connection_lost(str): Errore di apertura o disconnessione del cavo.
        status_message(str): Messaggi informativi per la status bar.
    """

    connected = pyqtSignal(str)
    sample_received = pyqtSignal(float, object)
    connection_lost = pyqtSignal(str)
    status_message = pyqtSignal(str)

    def __init__(
        self,
        port: str,
        baudrate: int = DEFAULT_BAUDRATE,
        num_channels: int = NUM_SENSORS,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self._port = port
        self._baudrate = baudrate
        self._num_channels = num_channels
        self._stop_event = threading.Event()
        # Contatori diagnostici (letti dalla GUI; int atomici sotto GIL).
        self.valid_packets: int = 0
        self.bad_packets: int = 0

    # ------------------------------------------------------------------ #
    # API pubblica
    # ------------------------------------------------------------------ #
    @property
    def port(self) -> str:
        """Nome della porta gestita dal worker."""
        return self._port

    def stop(self, timeout_ms: int = 2000) -> None:
        """Richiede l'arresto del thread e attende la sua terminazione."""
        self._stop_event.set()
        if self.isRunning():
            self.wait(timeout_ms)

    # ------------------------------------------------------------------ #
    # Corpo del thread
    # ------------------------------------------------------------------ #
    def run(self) -> None:  # noqa: D401 - override di QThread
        """Apre la porta e cicla finché non viene richiesto lo stop."""
        try:
            ser = serial.Serial(
                port=self._port,
                baudrate=self._baudrate,
                timeout=SERIAL_READ_TIMEOUT_S,
            )
        except (serial.SerialException, OSError, ValueError) as exc:
            self.connection_lost.emit(f"Impossibile aprire {self._port}: {exc}")
            return

        try:
            ser.reset_input_buffer()
            self.connected.emit(self._port)
            self.status_message.emit(
                f"Connesso a {self._port} @ {self._baudrate} baud"
            )
            self._read_loop(ser)
        finally:
            try:
                ser.close()
            except (serial.SerialException, OSError):
                # La porta può essere già sparita (cavo scollegato).
                self.status_message.emit("Porta chiusa (dispositivo assente)")

    def _read_loop(self, ser: serial.Serial) -> None:
        """Legge byte, ricompone le righe e le inoltra al parser."""
        buffer = bytearray()
        # La prima riga dopo l'apertura è quasi sempre troncata: si scarta.
        discard_first_line = True

        while not self._stop_event.is_set():
            try:
                waiting = ser.in_waiting
                chunk = ser.read(waiting if waiting > 0 else 1)
            except (serial.SerialException, OSError) as exc:
                if not self._stop_event.is_set():
                    self.connection_lost.emit(
                        f"Connessione persa su {self._port}: {exc}"
                    )
                return

            if not chunk:
                continue  # timeout: ricontrolla il flag di stop

            timestamp = time.perf_counter()
            buffer.extend(chunk)

            while True:
                newline_pos = buffer.find(b"\n")
                if newline_pos < 0:
                    break
                raw_line = bytes(buffer[:newline_pos])
                del buffer[: newline_pos + 1]

                if discard_first_line:
                    discard_first_line = False
                    continue
                self._handle_line(raw_line, timestamp)

            # Protezione contro flussi senza terminatore (baud errato, rumore).
            if len(buffer) > MAX_LINE_LENGTH:
                buffer.clear()
                self.bad_packets += 1

    def _handle_line(self, raw_line: bytes, timestamp: float) -> None:
        """Decodifica e valida una singola riga completa."""
        text = raw_line.decode("ascii", errors="replace")
        try:
            values = parse_line(text, self._num_channels)
        except PacketParseError:
            self.bad_packets += 1
            return
        self.valid_packets += 1
        self.sample_received.emit(timestamp, values)
