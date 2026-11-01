"""Setzt einen resumable Upload nach Verbindungsabbruechen fort. Ohne Google-Abhaengigkeit, damit die CI es testen kann."""
from __future__ import annotations

import time
from typing import Any, Callable

# So viele Fehler am Stueck ohne ein neu bestaetigtes Byte, bis der Upload aufgibt. Mit der Wartezeit unten sind das
# rund 5 Minuten, das ueberbrueckt auch einen kurzen DNS-Ausfall.
MAX_FAILS_WITHOUT_PROGRESS = 10
BACKOFF_STEP_SECONDS = 5


class ResumingUpload:
    """Wie `request.next_chunk()`, aber ein Abbruch aus [retryable] beendet den Upload nicht.

    `num_retries` der Bibliothek deckt SSL-Abbrueche, Lese-Timeouts und DNS-Ausfaelle nicht ab (2026-11-01: acht
    gescheiterte Versuche in Folge). Das gesetzte `_in_error_state` laesst die Bibliothek den Server fragen, welche
    Bytes angekommen sind, wie sie es selbst nach einem 5xx tut. Es gibt dafuer keine oeffentliche API.

    Der Zaehler gilt ueber alle Aufrufe: Nach einem Abbruch kehrt die Statusabfrage regulaer zurueck, ohne dass ein
    Byte dazugekommen ist. Nur echter Fortschritt setzt ihn zurueck, sonst liefe eine tote Leitung endlos.
    """

    def __init__(
        self,
        request: Any,
        *,
        retryable: tuple[type[BaseException], ...],
        num_retries: int = 0,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self._request = request
        self._retryable = retryable
        self._num_retries = num_retries
        self._sleep = sleep
        self._fails = 0
        self._offset = request.resumable_progress

    def next_chunk(self) -> tuple[Any, Any]:
        while True:
            try:
                result = self._request.next_chunk(num_retries=self._num_retries)
            except self._retryable as e:
                self._note_progress()
                self._fails += 1
                if self._fails > MAX_FAILS_WITHOUT_PROGRESS:
                    raise
                print(f"  Verbindung abgebrochen bei {self._offset / 1e6:.1f} MB ({type(e).__name__}), setze fort", flush=True)
                self._request._in_error_state = True
                self._sleep(self._fails * BACKOFF_STEP_SECONDS)
                continue
            self._note_progress()
            return result

    def _note_progress(self) -> None:
        if self._request.resumable_progress > self._offset:
            self._offset = self._request.resumable_progress
            self._fails = 0
