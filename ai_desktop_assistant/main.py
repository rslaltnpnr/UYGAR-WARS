"""
AI Kedi Asistani
-----------------
Windows masaustunde duran, seffaf arka planli, surklenebilir bir kedi
karakteri. Cift tiklaninca acilan konusma balonundan soru sorulur;
ekran goruntusu alinip Google Gemini Flash modeline gonderilir ve
yanit balonda gosterilir.

Calistirmak icin:
    pip install -r requirements.txt
    python main.py

Dosyanin en altinda PyInstaller ile tek dosya (.exe) yapma adimlari
yer alir.
"""

import hmac
import http.server
import ipaddress
import json
import os
import random
import socket
import ssl
import subprocess
import sys
import time
import traceback
import webbrowser
from urllib.parse import urlparse
from datetime import datetime

from PyQt6.QtCore import QObject, QPoint, Qt, QThread, QTimer, pyqtSignal
from PyQt6.QtGui import (
    QAction,
    QActionGroup,
    QBrush,
    QColor,
    QFont,
    QIcon,
    QPainter,
    QPen,
    QPixmap,
)
from PyQt6.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QInputDialog,
    QLineEdit,
    QMenu,
    QMessageBox,
    QPushButton,
    QSystemTrayIcon,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)


# --------------------------------------------------------------------------
# Yol yardimcilari (PyInstaller ile tek dosya .exe icinde de calisir)
# --------------------------------------------------------------------------

def base_dir():
    """config.json gibi yazilabilir dosyalarin duracagi klasor."""
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


def resource_path(relative_path):
    """assets gibi PyInstaller ile pakete gomulen salt-okunur dosyalar."""
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), relative_path)


CONFIG_PATH = os.path.join(base_dir(), "config.json")
HISTORY_PATH = os.path.join(base_dir(), "chat_history.json")
ASSETS_DIR = resource_path("assets")
MAX_HISTORY_ENTRIES = 200


# --------------------------------------------------------------------------
# Coken durumda log tutma + otomatik yeniden baslatma
# --------------------------------------------------------------------------

CRASH_LOG_PATH = os.path.join(base_dir(), "crash.log")
CRASH_MARKER_PATH = os.path.join(base_dir(), ".last_crash")
MIN_RESTART_INTERVAL_SECONDS = 10  # bundan kisa arayla ust uste cokerse
# yeniden baslatmayi durdurur (baslangicta patlayan bir hatanin sonsuz
# dongude bilgisayari yormasini onlemek icin)


def _restart_command():
    if getattr(sys, "frozen", False):
        return [sys.executable]
    return [sys.executable, os.path.abspath(__file__)]


def _log_crash(exc_type, exc_value, exc_tb):
    try:
        with open(CRASH_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(f"\n--- {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ---\n")
            traceback.print_exception(exc_type, exc_value, exc_tb, file=f)
    except OSError:
        pass


def _should_auto_restart():
    now = time.time()
    last = None
    try:
        with open(CRASH_MARKER_PATH, "r", encoding="utf-8") as f:
            last = float(f.read().strip())
    except (OSError, ValueError):
        pass
    try:
        with open(CRASH_MARKER_PATH, "w", encoding="utf-8") as f:
            f.write(str(now))
    except OSError:
        pass
    return last is None or (now - last) > MIN_RESTART_INTERVAL_SECONDS


def install_crash_handler():
    """
    Beklenmeyen bir hata GUI thread'inden disari sizarsa (PyQt6 normalde
    bunu yakalayip sys.excepthook'a yonlendirir) traceback'i crash.log'a
    yazar ve uygulamayi kendini yeniden baslatarak kurtarmaya calisir.
    Cok kisa arayla ust uste cokerse (baslangic hatasi dongusu) tekrar
    baslatmaz - kullanici crash.log'u inceleyip sorunu gormelidir.
    """

    def handle_exception(exc_type, exc_value, exc_tb):
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc_value, exc_tb)
            return
        _log_crash(exc_type, exc_value, exc_tb)
        if _should_auto_restart():
            try:
                subprocess.Popen(_restart_command(), close_fds=True)
            except OSError:
                pass
        os._exit(1)

    sys.excepthook = handle_exception

SLEEP_AFTER_MS = 3 * 60 * 1000  # 3 dakika hareketsizlikten sonra uyku
REVERT_TO_NORMAL_MS = 4000  # smile/fear gosterildikten sonra norm'a donus

FALLBACK_MODEL = "gemini-3.6-flash"
OVERLOAD_RETRY_DELAYS = (2, 4)  # saniye; ana modelde 503 aldiginda bekleme sureleri

# Google'in kullanimdan kaldirdigi/eskimis model adlari: config.json'da
# bunlardan biri kayitliysa otomatik olarak guncel varsayilana tasinir.
DEPRECATED_MODELS = {"gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.0-pro"}

STATE_FILES = {
    "norm": "fuff_norm.png",
    "zzz": "fuff_zzz.png",
    "smile": "fuff_smile.png",
    "stern": "fuff_stern.png",
    "fear": "fuff_fear.png",
}

REMOTE_SERVER_PORT = 8765
REMOTE_MAX_FAILED_ATTEMPTS = 5
REMOTE_LOCKOUT_SECONDS = 60

APP_VERSION = "1.1.0"
GITHUB_REPO = "rslaltnpnr/UYGAR-WARS"
UPDATE_CHECK_TIMEOUT_SECONDS = 5

DEFAULT_CONFIG = {
    "character_name": "Fuff",
    "gemini_api_key": "",
    "scale_percent": 100,
    "model_name": "gemini-flash-latest",
    "skin": "Varsayilan",
    "pos_x": None,
    "pos_y": None,
    "remote_pin": None,
    "gemini_request_date": None,
    "gemini_request_count": 0,
}


# --------------------------------------------------------------------------
# Ayar yonetimi (config.json)
# --------------------------------------------------------------------------

class ConfigManager:
    def __init__(self, path):
        self.path = path
        self.data = dict(DEFAULT_CONFIG)
        self.load()

    def load(self):
        if os.path.exists(self.path):
            try:
                with open(self.path, "r", encoding="utf-8") as f:
                    self.data.update(json.load(f))
            except (json.JSONDecodeError, OSError):
                pass
            self._migrate_deprecated_model()
        else:
            self.save()
        self._ensure_remote_pin()

    def _migrate_deprecated_model(self):
        if self.data.get("model_name") in DEPRECATED_MODELS:
            self.data["model_name"] = DEFAULT_CONFIG["model_name"]
            self.save()

    def _ensure_remote_pin(self):
        if not self.data.get("remote_pin"):
            self.data["remote_pin"] = f"{random.randint(0, 999999):06d}"
            self.save()

    def save(self):
        try:
            with open(self.path, "w", encoding="utf-8") as f:
                json.dump(self.data, f, ensure_ascii=False, indent=2)
        except OSError:
            pass

    def get(self, key):
        return self.data.get(key)

    def set(self, key, value):
        self.data[key] = value
        self.save()

    def register_gemini_request(self):
        """Gunluk soru sayacini bir arttirir (gun degistiyse once sifirlar)
        ve yeni degeri dondurur - kullaniciya gunde kac istek gonderdigini
        gostermek icin (Gemini ucretsiz kotasi gunluktur)."""
        today = datetime.now().strftime("%Y-%m-%d")
        if self.data.get("gemini_request_date") != today:
            self.data["gemini_request_date"] = today
            self.data["gemini_request_count"] = 0
        self.data["gemini_request_count"] += 1
        self.save()
        return self.data["gemini_request_count"]

    def gemini_request_count_today(self):
        today = datetime.now().strftime("%Y-%m-%d")
        if self.data.get("gemini_request_date") != today:
            return 0
        return self.data.get("gemini_request_count", 0)


# --------------------------------------------------------------------------
# Sohbet gecmisi (chat_history.json)
# --------------------------------------------------------------------------

class ChatHistoryManager:
    def __init__(self, path):
        self.path = path
        self.entries = []
        self.load()

    def load(self):
        if os.path.exists(self.path):
            try:
                with open(self.path, "r", encoding="utf-8") as f:
                    self.entries = json.load(f)
            except (json.JSONDecodeError, OSError):
                self.entries = []

    def save(self):
        try:
            with open(self.path, "w", encoding="utf-8") as f:
                json.dump(self.entries, f, ensure_ascii=False, indent=2)
        except OSError:
            pass

    def add(self, question, answer, is_error=False):
        self.entries.append(
            {
                "time": datetime.now().strftime("%Y-%m-%d %H:%M"),
                "question": question,
                "answer": answer,
                "is_error": is_error,
            }
        )
        if len(self.entries) > MAX_HISTORY_ENTRIES:
            self.entries = self.entries[-MAX_HISTORY_ENTRIES:]
        self.save()

    def clear(self):
        self.entries = []
        self.save()


# --------------------------------------------------------------------------
# Gorsel yukleme (assets eksikse basit bir yer tutucu cizilir)
# --------------------------------------------------------------------------

def discover_skins():
    """
    assets/ altindaki her alt klasoru ayri bir "skin" olarak sunar
    (fuff_norm.png vb. dosyalari icermesi beklenir). Kok dizindeki
    gorseller her zaman "Varsayilan" adiyla erisilebilir kalir, boylece
    yeni skin klasorleri eklemek mevcut kurulumu bozmaz.
    """
    skins = {"Varsayilan": ASSETS_DIR}
    if os.path.isdir(ASSETS_DIR):
        for name in sorted(os.listdir(ASSETS_DIR)):
            full_path = os.path.join(ASSETS_DIR, name)
            if os.path.isdir(full_path):
                skins[name] = full_path
    return skins


def make_placeholder_pixmap(size=96, color=QColor(90, 170, 255), label=""):
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setBrush(QBrush(color))
    painter.setPen(Qt.PenStyle.NoPen)
    painter.drawEllipse(4, 4, size - 8, size - 8)
    painter.setPen(QPen(QColor(255, 255, 255)))
    font = QFont()
    font.setPointSize(10)
    font.setBold(True)
    painter.setFont(font)
    painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, label)
    painter.end()
    return pixmap


def load_pixmap(skin_dir, filename, placeholder_label=""):
    path = os.path.join(skin_dir, filename)
    if os.path.exists(path):
        pixmap = QPixmap(path)
        if not pixmap.isNull():
            return pixmap
    return make_placeholder_pixmap(label=placeholder_label)


# --------------------------------------------------------------------------
# Uzaktan kumanda (telefon uygulamasindan yerel ag uzerinden komut)
# --------------------------------------------------------------------------

def get_local_ip():
    """Telefonun bu bilgisayara baglanacagi yerel ag IP'si (internete
    paket gondermeden, sadece isletim sistemine hangi arayuzun
    kullanilacagini sordurarak bulunur)."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        sock.close()
        return ip
    except OSError:
        return "127.0.0.1"


REMOTE_CERT_PATH = os.path.join(base_dir(), "remote_cert.pem")
REMOTE_KEY_PATH = os.path.join(base_dir(), "remote_key.pem")


def _generate_self_signed_cert():
    import datetime

    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "AI Kedi Asistani Uzaktan Kumanda")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=3650))
        .sign(key, hashes.SHA256())
    )

    key_pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    with open(REMOTE_KEY_PATH, "wb") as f:
        f.write(key_pem)
    with open(REMOTE_CERT_PATH, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))


def ensure_remote_tls_cert():
    """
    Uzaktan kumanda sunucusu icin kendinden imzali bir TLS sertifikasi/
    anahtari yoksa uretir; boylece PIN ve komutlar ag uzerinde duz metin
    degil sifreli gider (baskasi ayni Wi-Fi'de paketleri dinleyemez).
    Sertifika bir Yetkili Kurum tarafindan imzali olmadigindan telefon
    tarafi "ilk baglantida guven" (TOFU) modeliyle parmak izini sabitler.
    """
    if os.path.exists(REMOTE_CERT_PATH) and os.path.exists(REMOTE_KEY_PATH):
        return True
    try:
        _generate_self_signed_cert()
        return True
    except Exception:
        return False


def get_cert_fingerprint():
    """Sertifikanin SHA-256 parmak izini 'AA:BB:...' biciminde dondurur."""
    try:
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes

        with open(REMOTE_CERT_PATH, "rb") as f:
            cert = x509.load_pem_x509_certificate(f.read())
        digest = cert.fingerprint(hashes.SHA256()).hex()
        return ":".join(digest[i : i + 2] for i in range(0, len(digest), 2)).upper()
    except Exception:
        return None


def is_url_safe_to_open(url):
    """
    PIN sizarsa bile telefon uzerinden bilgisayarin yerel agindaki
    router/IoT/localhost panellerine yonlendirme (SSRF benzeri kotuye
    kullanim) yapilamamasi icin: yalnizca genel (ozel olmayan) IP'lere
    cozumlenen http(s) adreslerine izin verilir.

    Not: Bu, hedef host adini simdi cozup kontrol eder; gelismis bir
    saldirgan DNS rebinding ile bu kontrolden sonra farkli bir IP'ye
    yonlendirebilir - webbrowser.open() tarayiciya devrettigi icin bu
    katmanda tam engellenemez. Buradaki amac, PIN'i ele geciren birinin
    dogrudan "http://192.168.1.1/..." gibi bariz yerel adresler
    yazmasini engellemektir.
    """
    try:
        parsed = urlparse(url)
    except ValueError:
        return False
    if parsed.scheme not in ("http", "https"):
        return False
    hostname = parsed.hostname
    if not hostname or hostname.lower() == "localhost":
        return False
    try:
        infos = socket.getaddrinfo(hostname, None)
    except OSError:
        return False
    if not infos:
        return False
    for info in infos:
        raw_addr = info[4][0].split("%")[0]
        try:
            ip_obj = ipaddress.ip_address(raw_addr)
        except ValueError:
            return False
        if (
            ip_obj.is_private
            or ip_obj.is_loopback
            or ip_obj.is_link_local
            or ip_obj.is_reserved
            or ip_obj.is_multicast
            or ip_obj.is_unspecified
        ):
            return False
    return True


MEDIA_KEY_NAMES = {
    "play_pause": "play/pause media",
    "next": "next track",
    "prev": "previous track",
    "vol_up": "volume up",
    "vol_down": "volume down",
    "mute": "volume mute",
}

POWER_ACTIONS = ("sleep", "lock")


def handle_media_action(action):
    """Windows'ta medya tuslarini simule eder (keyboard kutuphanesi
    araciligiyla - global kisayol icin de kullanilan ayni kutuphane)."""
    if sys.platform != "win32":
        return False
    key = MEDIA_KEY_NAMES.get(action)
    if key is None:
        return False
    try:
        import keyboard

        keyboard.send(key)
        return True
    except Exception:
        return False


def handle_power_action(action):
    """Windows'ta bilgisayari kilitler ya da uyku moduna alir."""
    if sys.platform != "win32" or action not in POWER_ACTIONS:
        return False
    try:
        import ctypes

        if action == "lock":
            ctypes.windll.user32.LockWorkStation()
            return True
        # action == "sleep": hibernate degil normal uyku, zorla, uyanma
        # olaylarini devre disi birakma.
        ctypes.windll.powrprof.SetSuspendState(False, True, False)
        return True
    except Exception:
        return False


def capture_screenshot_jpeg_base64(max_width=1280, quality=70):
    """Ekran goruntusunu alip kucultup JPEG olarak base64 dondurur -
    telefona makul boyutta bir onizleme gondermek icin."""
    import base64
    import io

    import mss
    from PIL import Image

    with mss.mss() as sct:
        monitor = sct.monitors[0]
        shot = sct.grab(monitor)
    img = Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX")
    if img.width > max_width:
        ratio = max_width / img.width
        img = img.resize((max_width, max(1, int(img.height * ratio))))
    buffer = io.BytesIO()
    img.save(buffer, format="JPEG", quality=quality)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


class RemoteCommandServer(QThread):
    """
    Telefon uygulamasindan gelen komutlari alan basit bir yerel HTTP
    sunucusu. Sadece ayni Wi-Fi agindan erisim beklenir; PIN eslesmezse
    istek reddedilir. Uc noktalar:
      POST /open       {"pin", "url"}    - taraycida bir baglanti acar
      POST /media      {"pin", "action"} - medya tuslarini simule eder
      POST /power      {"pin", "action"} - kilitler / uyku moduna alir
      POST /screenshot {"pin"}           - kucultulmus bir ekran goruntusu dondurur
    Gecerli bir /open, /media ya da /power istegi geldiginde ilgili sinyal
    (ana/GUI thread'ine Qt tarafindan otomatik kuyruklanir) yayinlanir.
    """

    command_received = pyqtSignal(str)
    media_command_received = pyqtSignal(str)
    power_command_received = pyqtSignal(str)

    def __init__(self, config: ConfigManager, parent=None):
        super().__init__(parent)
        self.config = config
        self._httpd = None

    def run(self):
        config = self.config
        open_signal = self.command_received
        media_signal = self.media_command_received
        power_signal = self.power_command_received
        # IP -> {"count": basarisiz deneme sayisi, "blocked_until": epoch}
        # Kaba kuvvetle PIN denemeyi yavaslatmak icin bellek ici, basit bir
        # kilitlenme mekanizmasi (kalici loglama yapilmiyor).
        failed_attempts = {}

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format_str, *args):
                pass  # konsolu HTTP erisim loglariyla kirletme

            def _send_json(self, status, payload):
                body = json.dumps(payload).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                if self.path not in ("/open", "/media", "/power", "/screenshot"):
                    self._send_json(404, {"error": "bulunamadi"})
                    return

                client_ip = self.client_address[0]
                record = failed_attempts.get(client_ip)
                if record and time.time() < record["blocked_until"]:
                    remaining = int(record["blocked_until"] - time.time())
                    self._send_json(
                        429,
                        {"error": f"cok fazla yanlis deneme, {remaining} saniye sonra tekrar deneyin"},
                    )
                    return

                try:
                    length = int(self.headers.get("Content-Length", 0))
                    data = json.loads(self.rfile.read(length))
                except (ValueError, TypeError, json.JSONDecodeError):
                    self._send_json(400, {"error": "gecersiz istek govdesi"})
                    return

                submitted_pin = str(data.get("pin", ""))
                expected_pin = str(config.get("remote_pin"))
                if not hmac.compare_digest(submitted_pin, expected_pin):
                    record = failed_attempts.setdefault(client_ip, {"count": 0, "blocked_until": 0.0})
                    record["count"] += 1
                    if record["count"] >= REMOTE_MAX_FAILED_ATTEMPTS:
                        record["blocked_until"] = time.time() + REMOTE_LOCKOUT_SECONDS
                        record["count"] = 0
                    self._send_json(401, {"error": "gecersiz pin"})
                    return

                failed_attempts.pop(client_ip, None)

                if self.path == "/open":
                    url = str(data.get("url", "")).strip()
                    if not is_url_safe_to_open(url):
                        self._send_json(400, {"error": "gecersiz veya guvensiz url"})
                        return
                    open_signal.emit(url)
                    self._send_json(200, {"status": "ok"})
                    return

                if self.path == "/media":
                    action = str(data.get("action", ""))
                    if action not in MEDIA_KEY_NAMES:
                        self._send_json(400, {"error": "gecersiz eylem"})
                        return
                    media_signal.emit(action)
                    self._send_json(200, {"status": "ok"})
                    return

                if self.path == "/power":
                    action = str(data.get("action", ""))
                    if action not in POWER_ACTIONS:
                        self._send_json(400, {"error": "gecersiz eylem"})
                        return
                    power_signal.emit(action)
                    self._send_json(200, {"status": "ok"})
                    return

                # self.path == "/screenshot"
                try:
                    image_b64 = capture_screenshot_jpeg_base64()
                except Exception as exc:
                    self._send_json(500, {"error": f"ekran goruntusu alinamadi: {exc}"})
                    return
                self._send_json(200, {"status": "ok", "image_base64": image_b64})

        if not ensure_remote_tls_cert():
            return  # sertifika olusturulamadi - uzaktan kumanda olmadan devam et

        bind_ip = get_local_ip() or "0.0.0.0"
        try:
            self._httpd = http.server.ThreadingHTTPServer((bind_ip, REMOTE_SERVER_PORT), Handler)
        except OSError:
            try:
                self._httpd = http.server.ThreadingHTTPServer(("0.0.0.0", REMOTE_SERVER_PORT), Handler)
            except OSError:
                return

        try:
            ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ssl_context.load_cert_chain(REMOTE_CERT_PATH, REMOTE_KEY_PATH)
            self._httpd.socket = ssl_context.wrap_socket(self._httpd.socket, server_side=True)
        except (ssl.SSLError, OSError):
            self._httpd.server_close()
            self._httpd = None
            return

        self._httpd.daemon_threads = True
        try:
            self._httpd.serve_forever()
        except OSError:
            pass  # sunucu kapatildi vb.

    def stop(self):
        if self._httpd is not None:
            self._httpd.shutdown()


# --------------------------------------------------------------------------
# Guncelleme kontrolu (GitHub Releases)
# --------------------------------------------------------------------------

def _parse_version(text):
    """'v1.2.0' -> (1, 2, 0) gibi karsilastirilabilir bir tuple uretir;
    ayristirilamayan parcalar 0 sayilir."""
    text = text.strip()
    if text.lower().startswith("v"):
        text = text[1:]
    parts = []
    for piece in text.split("."):
        digits = "".join(ch for ch in piece if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts)


def is_newer_version(remote_version, local_version):
    try:
        return _parse_version(remote_version) > _parse_version(local_version)
    except (ValueError, TypeError):
        return False


class UpdateCheckWorker(QThread):
    """
    GitHub Releases API'sinden en son surumu sorar. Henuz hic release
    yayinlanmamissa (404) ya da ag erisimi yoksa sessizce hicbir sey
    yapmaz - bu, mevcut kurulumu bozmayan, tamamen opsiyonel bir kontrol.
    """

    update_available = pyqtSignal(str, str)  # tag_name, html_url
    check_finished = pyqtSignal(bool, str)  # basarili mi, hata mesaji (varsa)

    def run(self):
        try:
            import urllib.error
            import urllib.request

            url = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
            req = urllib.request.Request(
                url,
                headers={
                    "Accept": "application/vnd.github+json",
                    "User-Agent": "ai-kedi-asistani-update-check",
                },
            )
            with urllib.request.urlopen(req, timeout=UPDATE_CHECK_TIMEOUT_SECONDS) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                self.check_finished.emit(True, "")  # henuz release yayinlanmamis
            else:
                self.check_finished.emit(False, f"HTTP {exc.code}")
            return
        except Exception as exc:
            self.check_finished.emit(False, str(exc))
            return

        tag = str(data.get("tag_name", "")).strip()
        html_url = str(data.get("html_url", "")).strip()
        if tag and is_newer_version(tag, APP_VERSION):
            self.update_available.emit(tag, html_url)
        self.check_finished.emit(True, "")


# --------------------------------------------------------------------------
# Windows ile otomatik baslatma (baslangic klasoru yerine Run registry anahtari)
# --------------------------------------------------------------------------

AUTOSTART_VALUE_NAME = "AI Kedi Asistani"


def _autostart_command():
    if getattr(sys, "frozen", False):
        return f'"{sys.executable}"'
    return f'"{sys.executable}" "{os.path.abspath(__file__)}"'


def is_autostart_enabled():
    if sys.platform != "win32":
        return False
    try:
        import winreg

        key = winreg.OpenKey(
            winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", 0, winreg.KEY_READ
        )
        try:
            value, _ = winreg.QueryValueEx(key, AUTOSTART_VALUE_NAME)
            return value == _autostart_command()
        finally:
            winreg.CloseKey(key)
    except OSError:
        return False


def set_autostart(enabled):
    if sys.platform != "win32":
        return
    try:
        import winreg

        key = winreg.OpenKey(
            winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", 0, winreg.KEY_SET_VALUE
        )
        try:
            if enabled:
                winreg.SetValueEx(key, AUTOSTART_VALUE_NAME, 0, winreg.REG_SZ, _autostart_command())
            else:
                try:
                    winreg.DeleteValue(key, AUTOSTART_VALUE_NAME)
                except FileNotFoundError:
                    pass
        finally:
            winreg.CloseKey(key)
    except OSError:
        pass


# --------------------------------------------------------------------------
# Genel (uygulama odakta olmasa da calisan) klavye kisayolu
# --------------------------------------------------------------------------

HOTKEY_COMBO = "ctrl+shift+k"


class HotkeySignal(QObject):
    """
    keyboard kutuphanesi kendi arka plan thread'inde calisir; bu QObject
    Qt'nin sinyal/slot mekanizmasiyla tetiklemeyi ana/GUI thread'ine
    guvenli sekilde tasir.
    """

    triggered = pyqtSignal()


def register_global_hotkey(callback):
    """
    HOTKEY_COMBO tuş bileşimini global olarak dinler ve tetiklendiginde
    callback'i (Qt ana thread'inde) cagirir. Platform desteklemiyorsa ya
    da kayit basarisiz olursa (izin, cakisma vb.) sessizce hicbir sey
    yapmaz - uygulama bu ozellik olmadan da calismaya devam eder.
    """
    signal_holder = HotkeySignal()
    signal_holder.triggered.connect(callback)
    try:
        import keyboard

        keyboard.add_hotkey(HOTKEY_COMBO, signal_holder.triggered.emit)
    except Exception:
        return None
    return signal_holder  # referansi canli tutmak icin cagirana dondurulur


# --------------------------------------------------------------------------
# Ekran goruntusu + Gemini istegini arka planda yapan thread
# --------------------------------------------------------------------------

class GeminiWorker(QThread):
    finished_ok = pyqtSignal(str)
    finished_error = pyqtSignal(str)

    def __init__(self, api_key, model_name, question, character_name, parent=None):
        super().__init__(parent)
        self.api_key = api_key
        self.model_name = model_name
        self.question = question
        self.character_name = character_name

    def run(self):
        try:
            import mss
            import mss.tools

            with mss.mss() as sct:
                monitor = sct.monitors[0]  # tum sanal masaustu
                shot = sct.grab(monitor)
                png_bytes = mss.tools.to_png(shot.rgb, shot.size)
        except Exception as exc:
            self.finished_error.emit(f"Ekran goruntusu alinamadi: {exc}")
            return

        try:
            from google import genai
            from google.genai import types
        except ImportError:
            self.finished_error.emit(
                "google-genai kutuphanesi kurulu degil. "
                "'pip install google-genai' calistirin."
            )
            return

        persona = (
            f"Senin adin '{self.character_name}'. Kullanicinin masaustunde yasayan, "
            "onun ekranini gorebilen sevimli bir kedi yapay zeka asistanisin. "
            "Kendini her zaman bu isimle tanit; Google tarafindan gelistirilmis "
            "bir dil modeli oldugunu veya hangi sirkete/modele ait oldugunu "
            "asla soyleme. Kisa, samimi ve yardimsever konus."
        )
        contents = [
            self.question,
            types.Part.from_bytes(data=png_bytes, mime_type="image/png"),
        ]
        gen_config = types.GenerateContentConfig(system_instruction=persona)

        try:
            client = genai.Client(api_key=self.api_key)
            try:
                response = self._generate_with_retry(client, self.model_name, contents, gen_config)
            except Exception as primary_exc:
                should_try_fallback = self.model_name != FALLBACK_MODEL and (
                    self._is_overload_error(primary_exc) or self._is_model_retired_error(primary_exc)
                )
                if should_try_fallback:
                    try:
                        response = self._generate_with_retry(
                            client, FALLBACK_MODEL, contents, gen_config, retry_delays=(2,)
                        )
                    except Exception:
                        raise primary_exc
                else:
                    raise
            text = (response.text or "").strip() or "(Bos yanit dondu)"
            self.finished_ok.emit(text)
        except Exception as exc:
            self.finished_error.emit(f"Gemini API hatasi: {exc}")

    @staticmethod
    def _is_overload_error(exc):
        text = str(exc).lower()
        return "503" in text or "unavailable" in text or "overloaded" in text

    @staticmethod
    def _is_model_retired_error(exc):
        text = str(exc).lower()
        return "404" in text or "not_found" in text or "no longer available" in text

    def _generate_with_retry(self, client, model_name, contents, gen_config, retry_delays=OVERLOAD_RETRY_DELAYS):
        attempts = len(retry_delays) + 1
        for attempt in range(attempts):
            try:
                return client.models.generate_content(
                    model=model_name, contents=contents, config=gen_config
                )
            except Exception as exc:
                is_last_attempt = attempt == attempts - 1
                if is_last_attempt or not self._is_overload_error(exc):
                    raise
                time.sleep(retry_delays[attempt])


# --------------------------------------------------------------------------
# Konusma balonu
# --------------------------------------------------------------------------

class ChatBubble(QWidget):
    ask_requested = pyqtSignal(str)

    def __init__(self, character_name):
        super().__init__()
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setFixedSize(320, 220)
        self._build_ui(character_name)

    def _build_ui(self, character_name):
        container = QWidget(self)
        container.setGeometry(0, 0, self.width(), self.height())
        container.setObjectName("bubble")
        container.setStyleSheet(
            """
            #bubble {
                background-color: rgba(30, 30, 40, 220);
                border-radius: 16px;
                border: 1px solid rgba(255, 255, 255, 60);
            }
            QLabel { color: white; }
            QLineEdit {
                background-color: rgba(255, 255, 255, 30);
                border: 1px solid rgba(255, 255, 255, 80);
                border-radius: 8px;
                padding: 6px;
                color: white;
            }
            QPushButton {
                background-color: rgba(90, 170, 255, 220);
                border: none;
                border-radius: 8px;
                padding: 6px 10px;
                color: white;
                font-weight: bold;
            }
            QPushButton:hover { background-color: rgba(120, 190, 255, 230); }
            QTextEdit {
                background-color: rgba(255, 255, 255, 15);
                border: none;
                border-radius: 8px;
                color: white;
                padding: 6px;
            }
            """
        )

        layout = QVBoxLayout(container)
        layout.setContentsMargins(14, 12, 14, 12)

        header = QHBoxLayout()
        title = QPushButton(f"\U0001F431 {character_name}")
        title.setEnabled(False)
        title.setStyleSheet(
            "background: transparent; color: white; font-weight: bold; "
            "font-size: 13px; text-align: left; border: none; padding: 0;"
        )
        close_btn = QPushButton("✕")
        close_btn.setFixedSize(22, 22)
        close_btn.setStyleSheet(
            "background-color: rgba(255, 80, 80, 180); border-radius: 11px; padding: 0;"
        )
        close_btn.clicked.connect(self.close)
        header.addWidget(title)
        header.addStretch()
        header.addWidget(close_btn)
        layout.addLayout(header)

        self.response_area = QTextEdit()
        self.response_area.setReadOnly(True)
        self.response_area.setPlaceholderText("Bana ekraninda ne oldugunu sor...")
        layout.addWidget(self.response_area, 1)

        input_row = QHBoxLayout()
        self.input_field = QLineEdit()
        self.input_field.setPlaceholderText("Bir soru yaz...")
        self.input_field.returnPressed.connect(self._on_ask)
        self.ask_button = QPushButton("Sor / Fikir Ver")
        self.ask_button.clicked.connect(self._on_ask)
        input_row.addWidget(self.input_field, 1)
        input_row.addWidget(self.ask_button)
        layout.addLayout(input_row)

        self.request_count_label = QPushButton("")
        self.request_count_label.setEnabled(False)
        self.request_count_label.setStyleSheet(
            "background: transparent; color: rgba(255,255,255,140); "
            "font-size: 10px; text-align: left; border: none; padding: 0;"
        )
        layout.addWidget(self.request_count_label)

    def set_request_count(self, count):
        self.request_count_label.setText(f"Bugun gonderilen istek: {count}")

    def _on_ask(self):
        text = self.input_field.text().strip()
        if not text:
            return
        self.ask_requested.emit(text)

    def show_thinking(self):
        self.ask_button.setEnabled(False)
        self.response_area.setPlainText("Dusunuyor...")

    def show_response(self, text):
        self.ask_button.setEnabled(True)
        self.response_area.setPlainText(text)

    def show_error(self, text):
        self.ask_button.setEnabled(True)
        self.response_area.setPlainText(f"⚠ {text}")


# --------------------------------------------------------------------------
# Sohbet gecmisi paneli
# --------------------------------------------------------------------------

class ChatHistoryDialog(QWidget):
    def __init__(self, history: ChatHistoryManager, character_name):
        super().__init__()
        self.history = history
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setFixedSize(360, 420)
        self._build_ui(character_name)
        self.refresh()

    def _build_ui(self, character_name):
        container = QWidget(self)
        container.setGeometry(0, 0, self.width(), self.height())
        container.setObjectName("historyPanel")
        container.setStyleSheet(
            """
            #historyPanel {
                background-color: rgba(30, 30, 40, 220);
                border-radius: 16px;
                border: 1px solid rgba(255, 255, 255, 60);
            }
            QPushButton {
                background-color: rgba(90, 170, 255, 220);
                border: none;
                border-radius: 8px;
                padding: 6px 10px;
                color: white;
                font-weight: bold;
            }
            QPushButton:hover { background-color: rgba(120, 190, 255, 230); }
            QTextEdit {
                background-color: rgba(255, 255, 255, 15);
                border: none;
                border-radius: 8px;
                color: white;
                padding: 6px;
            }
            """
        )

        layout = QVBoxLayout(container)
        layout.setContentsMargins(14, 12, 14, 12)

        header = QHBoxLayout()
        title = QPushButton(f"\U0001F553 {character_name} - Sohbet Gecmisi")
        title.setEnabled(False)
        title.setStyleSheet(
            "background: transparent; color: white; font-weight: bold; "
            "font-size: 13px; text-align: left; border: none; padding: 0;"
        )
        close_btn = QPushButton("✕")
        close_btn.setFixedSize(22, 22)
        close_btn.setStyleSheet(
            "background-color: rgba(255, 80, 80, 180); border-radius: 11px; padding: 0;"
        )
        close_btn.clicked.connect(self.close)
        header.addWidget(title)
        header.addStretch()
        header.addWidget(close_btn)
        layout.addLayout(header)

        self.text_area = QTextEdit()
        self.text_area.setReadOnly(True)
        layout.addWidget(self.text_area, 1)

        footer = QHBoxLayout()
        footer.addStretch()
        clear_btn = QPushButton("Gecmisi Temizle")
        clear_btn.clicked.connect(self._on_clear)
        footer.addWidget(clear_btn)
        layout.addLayout(footer)

    def refresh(self):
        if not self.history.entries:
            self.text_area.setPlainText("Henuz bir sohbet gecmisi yok.")
            return
        lines = []
        for entry in reversed(self.history.entries):  # en yeni en ustte
            marker = "⚠" if entry.get("is_error") else "\U0001F431"
            lines.append(f"[{entry['time']}]")
            lines.append(f"Sen: {entry['question']}")
            lines.append(f"{marker} {entry['answer']}")
            lines.append("")
        self.text_area.setPlainText("\n".join(lines))

    def _on_clear(self):
        self.history.clear()
        self.refresh()


# --------------------------------------------------------------------------
# Masaustu kedi karakteri
# --------------------------------------------------------------------------

class CatCharacter(QWidget):
    SPRITE_BASE_SIZE = 110

    def __init__(self, config: ConfigManager):
        super().__init__()
        self.config = config

        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_NoSystemBackground)

        self.scale_factor = self.config.get("scale_percent") / 100.0
        self.pixmaps = {}
        self._load_pixmaps()

        self.state = "norm"
        self.current_pixmap = None
        self._dragging = False
        self._drag_offset = QPoint()
        self.last_activity = time.monotonic()
        self.bubble = None
        self.worker = None
        self.history = ChatHistoryManager(HISTORY_PATH)
        self.history_dialog = None
        self._pending_question = None

        self._position_window()
        self._set_state("norm")

        self.sleep_check_timer = QTimer(self)
        self.sleep_check_timer.timeout.connect(self._check_sleep)
        self.sleep_check_timer.start(5000)

        self.revert_timer = QTimer(self)
        self.revert_timer.setSingleShot(True)
        self.revert_timer.timeout.connect(lambda: self._set_state("norm"))

        self.remote_server = RemoteCommandServer(self.config, self)
        self.remote_server.command_received.connect(self._on_remote_command)
        self.remote_server.media_command_received.connect(self._on_media_command)
        self.remote_server.power_command_received.connect(self._on_power_command)
        self.remote_server.start()

        self._hotkey_signal = register_global_hotkey(self._open_bubble)

        self.tray_icon = None
        self._setup_tray_icon()

        self.update_worker = None
        self._update_check_manual = False
        self._last_update_info = None
        QTimer.singleShot(3000, lambda: self._check_for_updates(manual=False))

    # -- gorsel yukleme / olcekleme -------------------------------------

    def _load_pixmaps(self):
        skins = discover_skins()
        skin_dir = skins.get(self.config.get("skin"), ASSETS_DIR)
        for state, filename in STATE_FILES.items():
            raw = load_pixmap(skin_dir, filename, state)
            self.pixmaps[state] = raw.scaled(
                max(24, int(self.SPRITE_BASE_SIZE * self.scale_factor)),
                max(24, int(self.SPRITE_BASE_SIZE * self.scale_factor)),
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation,
            )

    def _position_window(self):
        screen = QApplication.primaryScreen().availableGeometry()
        w = self.pixmaps["norm"].width()
        h = self.pixmaps["norm"].height()

        saved_x = self.config.get("pos_x")
        saved_y = self.config.get("pos_y")
        if saved_x is not None and saved_y is not None:
            x = min(max(saved_x, screen.left()), screen.right() - w)
            y = min(max(saved_y, screen.top()), screen.bottom() - h)
        else:
            x = screen.right() - w - 40
            y = screen.bottom() - h - 20

        self.move(x, y)

    def _set_state(self, state):
        self.state = state
        pixmap = self.pixmaps.get(state, self.pixmaps["norm"])
        self.current_pixmap = pixmap
        self.setFixedSize(pixmap.size())
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
        if self.current_pixmap:
            painter.drawPixmap(0, 0, self.current_pixmap)

    # -- uyku modu ----------------------------------------------------------

    def _register_activity(self):
        self.last_activity = time.monotonic()
        if self.state == "zzz":
            self._set_state("norm")

    def _check_sleep(self):
        if self.state in ("stern",) or self._dragging:
            return
        if self.state == "zzz":
            return
        idle_ms = (time.monotonic() - self.last_activity) * 1000
        if idle_ms >= SLEEP_AFTER_MS:
            self.revert_timer.stop()
            self._set_state("zzz")

    # -- surukleme --------------------------------------------------------

    def mousePressEvent(self, event):
        self._register_activity()
        if event.button() == Qt.MouseButton.LeftButton:
            self._dragging = True
            self._drag_offset = event.globalPosition().toPoint() - self.pos()
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        if self._dragging and (event.buttons() & Qt.MouseButton.LeftButton):
            self.move(event.globalPosition().toPoint() - self._drag_offset)
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        if self._dragging:
            self._dragging = False
            self.config.set("pos_x", self.x())
            self.config.set("pos_y", self.y())
        super().mouseReleaseEvent(event)

    def mouseDoubleClickEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self._register_activity()
            self._open_bubble()
        super().mouseDoubleClickEvent(event)

    # -- konusma balonu -----------------------------------------------------

    def _open_bubble(self):
        if self.bubble is None:
            self.bubble = ChatBubble(self.config.get("character_name"))
            self.bubble.ask_requested.connect(self._handle_question)
            self.bubble.set_request_count(self.config.gemini_request_count_today())

        bubble_x = self.x() + self.width() // 2 - self.bubble.width() // 2
        bubble_y = self.y() - self.bubble.height() - 10

        screen = QApplication.primaryScreen().availableGeometry()
        bubble_x = max(screen.left(), min(bubble_x, screen.right() - self.bubble.width()))
        bubble_y = max(screen.top(), bubble_y)

        self.bubble.move(bubble_x, bubble_y)
        self.bubble.show()
        self.bubble.raise_()
        self.bubble.activateWindow()

    def _open_history(self):
        if self.history_dialog is None:
            self.history_dialog = ChatHistoryDialog(self.history, self.config.get("character_name"))
        self.history_dialog.refresh()

        panel_x = self.x() + self.width() // 2 - self.history_dialog.width() // 2
        panel_y = self.y() - self.history_dialog.height() - 10

        screen = QApplication.primaryScreen().availableGeometry()
        panel_x = max(screen.left(), min(panel_x, screen.right() - self.history_dialog.width()))
        panel_y = max(screen.top(), panel_y)

        self.history_dialog.move(panel_x, panel_y)
        self.history_dialog.show()
        self.history_dialog.raise_()
        self.history_dialog.activateWindow()

    def _handle_question(self, question):
        api_key = self.config.get("gemini_api_key")
        if not api_key:
            self.bubble.show_error("Once sag tik menusunden Gemini API Key ayarini girin.")
            return

        self._register_activity()
        self.revert_timer.stop()
        self._set_state("stern")
        self.bubble.show_thinking()
        self.bubble.set_request_count(self.config.register_gemini_request())
        self._pending_question = question

        self.worker = GeminiWorker(
            api_key,
            self.config.get("model_name"),
            question,
            self.config.get("character_name"),
        )
        self.worker.finished_ok.connect(self._on_answer)
        self.worker.finished_error.connect(self._on_answer_error)
        self.worker.start()

    def _on_answer(self, text):
        self._set_state("smile")
        self.revert_timer.start(REVERT_TO_NORMAL_MS)
        if self.bubble:
            self.bubble.show_response(text)
        self._log_history(text, is_error=False)

    def _on_answer_error(self, text):
        self._set_state("fear")
        self.revert_timer.start(REVERT_TO_NORMAL_MS)
        if self.bubble:
            self.bubble.show_error(text)
        self._log_history(text, is_error=True)

    def _log_history(self, answer, is_error):
        if self._pending_question is None:
            return
        self.history.add(self._pending_question, answer, is_error=is_error)
        self._pending_question = None
        if self.history_dialog is not None:
            self.history_dialog.refresh()

    # -- uzaktan kumanda ------------------------------------------------------

    def _on_remote_command(self, url):
        webbrowser.open(url)
        self._register_activity()
        self.revert_timer.stop()
        self._set_state("smile")
        self.revert_timer.start(REVERT_TO_NORMAL_MS)

    def _on_media_command(self, action):
        handle_media_action(action)
        self._register_activity()
        self.revert_timer.stop()
        self._set_state("smile")
        self.revert_timer.start(REVERT_TO_NORMAL_MS)

    def _on_power_command(self, action):
        handle_power_action(action)

    def _show_remote_info(self):
        self._register_activity()
        ip = get_local_ip()
        pin = self.config.get("remote_pin")
        fingerprint = get_cert_fingerprint()
        fingerprint_line = (
            f"Sertifika Parmak Izi (SHA-256): {fingerprint}\n"
            if fingerprint
            else ""
        )
        box = QMessageBox(self)
        box.setWindowTitle("Uzaktan Kumanda")
        box.setText(
            "Telefon uygulamasindaki \"Bilgisayari Kumanda Et\" bolumune "
            "bu bilgileri girin (ikisi de ayni Wi-Fi agina bagli olmali). "
            "Baglanti HTTPS (TLS) ile sifrelenir; telefon ilk baglantida "
            "asagidaki parmak izini kaydedip sonraki baglantilarda dogrular:\n\n"
            f"IP Adresi: {ip}\n"
            f"Port: {REMOTE_SERVER_PORT}\n"
            f"PIN: {pin}\n"
            f"{fingerprint_line}"
        )
        regen_button = box.addButton("PIN'i Yenile", QMessageBox.ButtonRole.ActionRole)
        box.addButton(QMessageBox.StandardButton.Close)
        box.exec()
        if box.clickedButton() == regen_button:
            self.config.set("remote_pin", f"{random.randint(0, 999999):06d}")
            self._show_remote_info()

    # -- hatirlatici --------------------------------------------------------

    def _create_reminder(self):
        self._register_activity()
        minutes, ok = QInputDialog.getInt(
            self, "Hatirlatici Kur", "Kac dakika sonra hatirlatilsin?", 5, 1, 1440
        )
        if not ok:
            return
        text, ok = QInputDialog.getText(
            self, "Hatirlatici Kur", "Hatirlatma mesaji (bos birakabilirsiniz):"
        )
        if not ok:
            return
        text = text.strip() or "Hatirlatma zamani!"

        QTimer.singleShot(minutes * 60 * 1000, lambda: self._fire_reminder(text))

        if self.tray_icon is not None:
            self.tray_icon.showMessage(
                "Hatirlatici Kuruldu",
                f"{minutes} dakika sonra hatirlatilacaksiniz.",
                QSystemTrayIcon.MessageIcon.Information,
                4000,
            )
        else:
            QMessageBox.information(
                self, "Hatirlatici Kuruldu", f"{minutes} dakika sonra hatirlatilacaksiniz."
            )

    def _fire_reminder(self, text):
        self._register_activity()
        self.revert_timer.stop()
        self._set_state("smile")
        self.revert_timer.start(REVERT_TO_NORMAL_MS)
        if self.tray_icon is not None:
            self.tray_icon.showMessage(
                f"{self.config.get('character_name')} Hatirlatiyor",
                text,
                QSystemTrayIcon.MessageIcon.Information,
                10000,
            )
        else:
            QMessageBox.information(self, "Hatirlatma", text)

    # -- guncelleme kontrolu ----------------------------------------------

    def _check_for_updates(self, manual=False):
        if self.update_worker is not None and self.update_worker.isRunning():
            return
        self._update_check_manual = manual
        self._last_update_info = None
        self.update_worker = UpdateCheckWorker(self)
        self.update_worker.update_available.connect(self._on_update_available)
        self.update_worker.check_finished.connect(self._on_update_check_finished)
        self.update_worker.start()

    def _on_update_available(self, tag, html_url):
        self._last_update_info = (tag, html_url)
        if not self._update_check_manual and self.tray_icon is not None:
            self.tray_icon.showMessage(
                "Yeni surum mevcut",
                f"AI Kedi Asistani {tag} yayinlandi. GitHub'dan indirebilirsiniz.",
                QSystemTrayIcon.MessageIcon.Information,
                8000,
            )

    def _on_update_check_finished(self, success, error_message):
        if not self._update_check_manual:
            return
        if not success:
            QMessageBox.warning(
                self, "Guncelleme Kontrolu", f"Guncelleme kontrol edilemedi: {error_message}"
            )
            return
        if self._last_update_info is not None:
            tag, html_url = self._last_update_info
            QMessageBox.information(
                self,
                "Guncelleme Mevcut",
                f"Yeni surum mevcut: {tag} (su an: {APP_VERSION})\n\n{html_url}",
            )
        else:
            QMessageBox.information(
                self, "Guncelleme Kontrolu", f"Kullandiginiz surum guncel ({APP_VERSION})."
            )

    # -- sistem tepsisi -------------------------------------------------------

    def _setup_tray_icon(self):
        if not QSystemTrayIcon.isSystemTrayAvailable():
            return
        self.tray_icon = QSystemTrayIcon(QIcon(self.pixmaps["norm"]), self)
        self.tray_icon.setToolTip(self.config.get("character_name"))

        tray_menu = QMenu()
        show_action = QAction("Goster", self)
        show_action.triggered.connect(self._restore_from_tray)
        tray_menu.addAction(show_action)
        tray_menu.addSeparator()
        exit_action = QAction("Cikis", self)
        exit_action.triggered.connect(QApplication.instance().quit)
        tray_menu.addAction(exit_action)

        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.activated.connect(self._on_tray_activated)
        self.tray_icon.show()

    def _on_tray_activated(self, reason):
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self._restore_from_tray()

    def _restore_from_tray(self):
        self.show()
        self.raise_()
        self.activateWindow()

    def _toggle_autostart(self, checked):
        set_autostart(checked)

    # -- sag tik menusu -----------------------------------------------------

    def contextMenuEvent(self, event):
        self._register_activity()
        menu = QMenu(self)
        menu.setStyleSheet(
            """
            QMenu { background-color: #202028; color: white; border: 1px solid #444; }
            QMenu::item { padding: 6px 20px; }
            QMenu::item:selected { background-color: #3a6cf6; }
            """
        )

        size_menu = menu.addMenu("Boyut Degistir")
        size_group = QActionGroup(self)
        size_group.setExclusive(True)
        for percent in (50, 75, 100, 150):
            action = QAction(f"%{percent}", self)
            action.setCheckable(True)
            action.setChecked(self.config.get("scale_percent") == percent)
            action.triggered.connect(lambda checked, p=percent: self._set_scale(p))
            size_group.addAction(action)
            size_menu.addAction(action)

        skins = discover_skins()
        if len(skins) > 1:
            skin_menu = menu.addMenu("Kedi Skin'i")
            skin_group = QActionGroup(self)
            skin_group.setExclusive(True)
            current_skin = self.config.get("skin")
            for skin_name in skins:
                action = QAction(skin_name, self)
                action.setCheckable(True)
                action.setChecked(skin_name == current_skin)
                action.triggered.connect(lambda checked, s=skin_name: self._set_skin(s))
                skin_group.addAction(action)
                skin_menu.addAction(action)

        rename_action = QAction("Kediye Isim Ver", self)
        rename_action.triggered.connect(self._rename_character)
        menu.addAction(rename_action)

        history_action = QAction("Sohbet Gecmisi", self)
        history_action.triggered.connect(self._open_history)
        menu.addAction(history_action)

        api_key_action = QAction("Gemini API Key Ayarlari", self)
        api_key_action.triggered.connect(self._set_api_key)
        menu.addAction(api_key_action)

        remote_action = QAction("Uzaktan Kumanda Bilgisi", self)
        remote_action.triggered.connect(self._show_remote_info)
        menu.addAction(remote_action)

        reminder_action = QAction("Hatirlatici Kur", self)
        reminder_action.triggered.connect(self._create_reminder)
        menu.addAction(reminder_action)

        autostart_action = QAction("Windows ile Baslat", self)
        autostart_action.setCheckable(True)
        autostart_action.setChecked(is_autostart_enabled())
        autostart_action.toggled.connect(self._toggle_autostart)
        menu.addAction(autostart_action)

        update_action = QAction("Guncellemeleri Kontrol Et", self)
        update_action.triggered.connect(lambda: self._check_for_updates(manual=True))
        menu.addAction(update_action)

        menu.addSeparator()
        exit_action = QAction("Cikis", self)
        exit_action.triggered.connect(QApplication.instance().quit)
        menu.addAction(exit_action)

        menu.exec(event.globalPos())

    def _set_scale(self, percent):
        self.config.set("scale_percent", percent)
        self.scale_factor = percent / 100.0
        old_x, old_y = self.x(), self.y()

        self._load_pixmaps()
        self._set_state(self.state)

        screen = QApplication.primaryScreen().availableGeometry()
        new_x = min(max(old_x, screen.left()), screen.right() - self.width())
        new_y = min(max(old_y, screen.top()), screen.bottom() - self.height())
        self.move(new_x, new_y)
        self.config.set("pos_x", new_x)
        self.config.set("pos_y", new_y)

    def _set_skin(self, skin_name):
        self.config.set("skin", skin_name)
        old_x, old_y = self.x(), self.y()

        self._load_pixmaps()
        self._set_state(self.state)

        screen = QApplication.primaryScreen().availableGeometry()
        new_x = min(max(old_x, screen.left()), screen.right() - self.width())
        new_y = min(max(old_y, screen.top()), screen.bottom() - self.height())
        self.move(new_x, new_y)
        self.config.set("pos_x", new_x)
        self.config.set("pos_y", new_y)

    def _rename_character(self):
        current = self.config.get("character_name")
        name, ok = QInputDialog.getText(self, "Kediye Isim Ver", "Yeni isim:", text=current)
        if ok and name.strip():
            self.config.set("character_name", name.strip())
            self.bubble = None  # yeni isimle yeniden olusturulsun
            self.history_dialog = None  # yeni isimle yeniden olusturulsun

    def _set_api_key(self):
        current = self.config.get("gemini_api_key")
        key, ok = QInputDialog.getText(
            self,
            "Gemini API Key Ayarlari",
            "API anahtarinizi girin:",
            QLineEdit.EchoMode.Password,
            current,
        )
        if ok:
            self.config.set("gemini_api_key", key.strip())


# --------------------------------------------------------------------------
# Giris noktasi
# --------------------------------------------------------------------------

def main():
    install_crash_handler()
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    config = ConfigManager(CONFIG_PATH)
    cat = CatCharacter(config)
    cat.show()

    app.aboutToQuit.connect(cat.remote_server.stop)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()


# ==========================================================================
# PyInstaller ile tek dosya (.exe) yapma adimlari (Windows)
# ==========================================================================
#
# 1) Sanal ortam olusturup bagimliliklari kurun:
#
#       python -m venv venv
#       venv\Scripts\activate
#       pip install -r requirements.txt
#       pip install pyinstaller
#
# 2) "assets" klasorunun bu dosyayla (main.py) ayni klasorde oldugundan
#    emin olun (fuff_norm.png, fuff_zzz.png, fuff_smile.png,
#    fuff_stern.png, fuff_fear.png).
#
# 3) Proje klasorunde asagidaki komutu calistirin. --add-data ile assets
#    klasoru exe'nin icine gomulur (Windows'ta kaynak ve hedef ";" ile
#    ayrilir):
#
#       pyinstaller --onefile --windowed --name "AI-Kedi-Asistani" ^
#           --add-data "assets;assets" main.py
#
#    Ozel bir uygulama simgesi eklemek isterseniz (icon.ico dosyasi ile):
#
#       pyinstaller --onefile --windowed --name "AI-Kedi-Asistani" ^
#           --add-data "assets;assets" --icon "icon.ico" main.py
#
# 4) Derleme bitince exe dosyasi "dist\AI-Kedi-Asistani.exe" altinda
#    olusur. config.json, exe ilk calistirildiginda exe ile ayni klasorde
#    otomatik olarak olusturulur (API anahtari ve pozisyon orada saklanir).
#
# 5) --windowed bayragi konsol penceresini gizler. Hata ayiklarken
#    gecici olarak bu bayragi kaldirip konsolu gorebilirsiniz.
#
# Not: --onefile modunda uygulama her acildiginda assets klasorunu gecici
# bir klasore (sys._MEIPASS) acar; koddaki resource_path() fonksiyonu bunu
# otomatik olarak yonetir, ek bir islem yapmaniza gerek yoktur.
# ==========================================================================
