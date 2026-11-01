"""Tests fuer tools/resumable_upload.py. Aufruf: python tools/test_resumable_upload.py"""
import ssl
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import resumable_upload as m  # noqa: E402

results = []


def check(name, cond):
    results.append(bool(cond))
    print(("PASS " if cond else "FAIL ") + name)


class FakeRequest:
    """Spielt Schritte ab: Ausnahme = Abbruch, Zahl = bestaetigter Stand (bleibt er gleich, gab es keinen Fortschritt)."""

    def __init__(self, steps):
        self.steps = list(steps)
        self.resumable_progress = 0
        self._in_error_state = False
        self.error_state_seen = []
        self.num_retries_seen = []

    def next_chunk(self, num_retries=0):
        self.error_state_seen.append(self._in_error_state)
        self.num_retries_seen.append(num_retries)
        self._in_error_state = False
        step = self.steps.pop(0)
        if isinstance(step, BaseException):
            raise step
        self.resumable_progress = step
        return ("status", None)


def uploader(request, retryable=(OSError,)):
    sleeps = []
    return m.ResumingUpload(request, retryable=retryable, num_retries=5, sleep=sleeps.append), sleeps


# Ohne Abbruch: reicht das Ergebnis durch, wartet nicht
req = FakeRequest([100])
up, sleeps = uploader(req)
check("ohne Abbruch kommt das Ergebnis durch", up.next_chunk() == ("status", None) and sleeps == [])
check("num_retries wird weitergereicht", req.num_retries_seen == [5])
check("ohne Abbruch kein Fehlerzustand", req.error_state_seen == [False])

# SSL-Abbruch, Timeout: naechster Aufruf fragt den Server nach dem Stand
req = FakeRequest([ssl.SSLEOFError(), TimeoutError(), 100])
up, sleeps = uploader(req)
check("setzt nach SSL-Abbruch und Timeout fort", up.next_chunk() == ("status", None) and req.resumable_progress == 100)
check("Fortsetzung laeuft ueber den Fehlerzustand", req.error_state_seen == [False, True, True])
check("Wartezeit steigt", sleeps == [5, 10])


# Eigene Fehlerklasse, wie httplib2.ServerNotFoundError (kein OSError)
class DnsError(Exception):
    pass


up, _ = uploader(FakeRequest([DnsError(), 100]), retryable=(OSError, DnsError))
check("DNS-Ausfall wird fortgesetzt, wenn er in retryable steht", up.next_chunk() == ("status", None))

# Andere Fehler (z.B. HttpError 403) gehen sofort durch
req = FakeRequest([ValueError("403")])
up, sleeps = uploader(req)
try:
    up.next_chunk()
    check("fremder Fehler geht durch", False)
except ValueError:
    check("fremder Fehler geht durch", sleeps == [])

# Aufgeben ohne Fortschritt
req = FakeRequest([OSError()] * (m.MAX_FAILS_WITHOUT_PROGRESS + 1))
up, sleeps = uploader(req)
try:
    up.next_chunk()
    check("gibt ohne Fortschritt auf", False)
except OSError:
    check("gibt ohne Fortschritt auf", len(sleeps) == m.MAX_FAILS_WITHOUT_PROGRESS and req.steps == [])

# Tote Leitung: Die Statusabfrage klappt jedes Mal (kehrt regulaer zurueck), der Block bricht wieder ab. Das darf
# nicht endlos laufen, auch wenn jeder Aufruf fuer sich erfolgreich endet.
req = FakeRequest([OSError(), 0] * (m.MAX_FAILS_WITHOUT_PROGRESS + 1))
up, sleeps = uploader(req)
try:
    for _ in range(m.MAX_FAILS_WITHOUT_PROGRESS + 1):
        up.next_chunk()
    check("Statusabfrage ohne Fortschritt zaehlt nicht als Erfolg", False)
except OSError:
    check("Statusabfrage ohne Fortschritt zaehlt nicht als Erfolg", len(sleeps) == m.MAX_FAILS_WITHOUT_PROGRESS)

# Echter Fortschritt setzt den Zaehler zurueck: viel mehr Abbrueche als das Limit, aber jeder bringt Bytes
steps = []
for i in range(1, m.MAX_FAILS_WITHOUT_PROGRESS * 3):
    steps += [OSError(), i * 100]
req = FakeRequest(steps)
up, sleeps = uploader(req)
while req.steps:
    up.next_chunk()
check("Fortschritt setzt den Fehlerzaehler zurueck", max(sleeps) == m.BACKOFF_STEP_SECONDS)

print(f"{sum(results)}/{len(results)} bestanden")
sys.exit(0 if all(results) else 1)
