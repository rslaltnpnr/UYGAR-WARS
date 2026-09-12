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
from collections import deque
from datetime import datetime
from urllib.parse import urlparse

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
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMenu,
    QMessageBox,
    QProgressDialog,
    QPushButton,
    QScrollArea,
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

APP_VERSION = "1.2.2"
GITHUB_REPO = "rslaltnpnr/UYGAR-WARS"
UPDATE_CHECK_TIMEOUT_SECONDS = 5
UPDATE_DOWNLOAD_TIMEOUT_SECONDS = 60
# release-desktop.yml release'e bu adlarla dosya yukler - degistirilirse
# ikisi de birlikte guncellenmeli.
UPDATE_ASSET_NAME = "AI-Kedi-Asistani.exe"
UPDATE_CHECKSUM_ASSET_NAME = "AI-Kedi-Asistani.exe.sha256"

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
    "theme_mode": "dark",
}

# Konusma balonu ve gecmis paneli gibi yari-seffaf panellerin renk paleti.
# Mobil uygulamadaki ThemeMode.light/dark tercihiyle ayni fikirde -
# "theme_mode" config anahtari yedek alma/geri yukleme ile diger tum
# ayarlar gibi tasinir, boylece iki uygulamada da tutarli bir tercih
# saklanir (gercek bir canli senkron degil, ayri ayri saklanan ayni tur
# tercih).
THEME_PALETTES = {
    "dark": {
        "panel_bg": "rgba(30, 30, 40, 220)",
        "border": "rgba(255, 255, 255, 60)",
        "text": "white",
        "text_muted": "rgba(255, 255, 255, 140)",
        "input_bg": "rgba(255, 255, 255, 30)",
        "input_border": "rgba(255, 255, 255, 80)",
        "textedit_bg": "rgba(255, 255, 255, 15)",
    },
    "light": {
        "panel_bg": "rgba(245, 245, 250, 235)",
        "border": "rgba(0, 0, 0, 40)",
        "text": "#202028",
        "text_muted": "rgba(30, 30, 40, 140)",
        "input_bg": "rgba(0, 0, 0, 18)",
        "input_border": "rgba(0, 0, 0, 60)",
        "textedit_bg": "rgba(0, 0, 0, 10)",
    },
}


def panel_stylesheet(object_name, theme_mode):
    """[object_name] nesne adiyla iliskilendirilmis yari-seffaf bir panel
    (ChatBubble/ChatHistoryDialog) icin, [theme_mode] ("dark"/"light")
    paletine gore QSS dondurur. Ikisi de neredeyse ayni QSS blogunu
    kullandigi icin buraya cikarildi."""
    p = THEME_PALETTES.get(theme_mode, THEME_PALETTES["dark"])
    return f"""
        #{object_name} {{
            background-color: {p['panel_bg']};
            border-radius: 16px;
            border: 1px solid {p['border']};
        }}
        QLabel {{ color: {p['text']}; }}
        QLineEdit {{
            background-color: {p['input_bg']};
            border: 1px solid {p['input_border']};
            border-radius: 8px;
            padding: 6px;
            color: {p['text']};
        }}
        QPushButton {{
            background-color: rgba(90, 170, 255, 220);
            border: none;
            border-radius: 8px;
            padding: 6px 10px;
            color: white;
            font-weight: bold;
        }}
        QPushButton:hover {{ background-color: rgba(120, 190, 255, 230); }}
        QTextEdit {{
            background-color: {p['textedit_bg']};
            border: none;
            border-radius: 8px;
            color: {p['text']};
            padding: 6px;
        }}
    """


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
                "favorite": False,
            }
        )
        if len(self.entries) > MAX_HISTORY_ENTRIES:
            self.entries = self.entries[-MAX_HISTORY_ENTRIES:]
        self.save()

    def clear(self):
        self.entries = []
        self.save()


def merge_history_entries(existing_entries, new_entries):
    """[new_entries] icindeki (telefondan gelen) kayitlari [existing_entries]
    listesine yerinde (in-place) ekler; (time, question, answer) ucluesu
    zaten varsa atlar. Alan uzunluklari HISTORY_ENTRY_MAX_FIELD_LENGTH ile
    sinirlanir. time ya da question bossa kayit atlanir. Eklenen kayit
    sayisini dondurur."""
    existing_keys = {
        (e.get("time"), e.get("question"), e.get("answer")) for e in existing_entries
    }
    added = 0
    for entry in new_entries:
        if not isinstance(entry, dict):
            continue
        entry_time = str(entry.get("time", ""))[:64]
        question = str(entry.get("question", ""))[:HISTORY_ENTRY_MAX_FIELD_LENGTH]
        answer = str(entry.get("answer", ""))[:HISTORY_ENTRY_MAX_FIELD_LENGTH]
        if not entry_time or not question:
            continue
        key = (entry_time, question, answer)
        if key in existing_keys:
            continue
        existing_keys.add(key)
        existing_entries.append(
            {
                "time": entry_time,
                "question": question,
                "answer": answer,
                "is_error": bool(entry.get("is_error", False)),
            }
        )
        added += 1
    return added


def format_history_entries(entries):
    """[entries] listesini (en yeni en ustte) okunabilir duz metne cevirir -
    hem ChatHistoryDialog'un ekran gorunumu hem de disa aktarma (.txt)
    ayni bicimi kullanir."""
    lines = []
    for entry in reversed(entries):
        marker = "⚠" if entry.get("is_error") else "\U0001F431"
        lines.append(f"[{entry.get('time', '')}]")
        lines.append(f"Sen: {entry.get('question', '')}")
        lines.append(f"{marker} {entry.get('answer', '')}")
        lines.append("")
    return "\n".join(lines)


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

CLIPBOARD_ACTIONS = ("push", "pull")
CLIPBOARD_MAX_LENGTH = 100_000

# Telefondan /history/import ile tek seferde ice aktarilabilecek en fazla
# kayit sayisi ve soru/cevap basina en fazla karakter (PIN'i ele geciren
# birinin sohbet gecmisini sisirmesini/asiri bellek kullanimini
# engellemek icin).
HISTORY_IMPORT_MAX_ENTRIES = 500
HISTORY_ENTRY_MAX_FIELD_LENGTH = 20_000


def get_clipboard_text():
    try:
        return QApplication.clipboard().text()
    except Exception:
        return ""


def set_clipboard_text(text):
    try:
        QApplication.clipboard().setText(text)
        return True
    except Exception:
        return False


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
      POST /history    {"pin"}               - sohbet gecmisini dondurur (telefona ice aktarmak icin)
      POST /history/import {"pin", "entries"} - telefondaki yeni kayitlari sohbet gecmisine ekler (iki yonlu senkron)
      POST /alerts     {"pin", "since_id"}   - since_id'den sonraki hata/uyari bildirimlerini dondurur
      POST /clipboard  {"pin", "action", "text"} - "push": panoyu text'e ayarlar, "pull": panoyu dondurur
    Gecerli bir /open, /media ya da /power istegi geldiginde ilgili sinyal
    (ana/GUI thread'ine Qt tarafindan otomatik kuyruklanir) yayinlanir.
    """

    command_received = pyqtSignal(str)
    media_command_received = pyqtSignal(str)
    power_command_received = pyqtSignal(str)

    MAX_ALERTS = 50

    def __init__(self, config: ConfigManager, history: ChatHistoryManager, parent=None):
        super().__init__(parent)
        self.config = config
        self.history = history
        self._httpd = None
        # Telefonun yokladigi (poll) hata/uyari kuyrugu - deque kullanilir
        # cunku Handler thread'i bu listeyi (yeniden atama degil, sadece
        # append/otomatik-trim ile) referans olarak paylasir.
        self.alerts = deque(maxlen=self.MAX_ALERTS)
        self._next_alert_id = 1

    def add_alert(self, message):
        """Ana/GUI thread'inden cagrilir (orn. bir Gemini hatasi olustugunda);
        telefon /alerts ile bir sonraki yoklamasinda bunu gorur."""
        self.alerts.append(
            {
                "id": self._next_alert_id,
                "time": datetime.now().strftime("%Y-%m-%d %H:%M"),
                "message": str(message),
            }
        )
        self._next_alert_id += 1

    def run(self):
        config = self.config
        history = self.history
        alerts = self.alerts
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
                if self.path not in (
                    "/open",
                    "/media",
                    "/power",
                    "/screenshot",
                    "/history",
                    "/history/import",
                    "/alerts",
                    "/clipboard",
                ):
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

                if self.path == "/screenshot":
                    try:
                        image_b64 = capture_screenshot_jpeg_base64()
                    except Exception as exc:
                        self._send_json(500, {"error": f"ekran goruntusu alinamadi: {exc}"})
                        return
                    self._send_json(200, {"status": "ok", "image_base64": image_b64})
                    return

                if self.path == "/history":
                    self._send_json(200, {"status": "ok", "entries": history.entries})
                    return

                if self.path == "/history/import":
                    entries = data.get("entries")
                    if not isinstance(entries, list):
                        self._send_json(400, {"error": "gecersiz govde"})
                        return
                    if len(entries) > HISTORY_IMPORT_MAX_ENTRIES:
                        self._send_json(400, {"error": "cok fazla kayit"})
                        return
                    added = merge_history_entries(history.entries, entries)
                    if added:
                        if len(history.entries) > MAX_HISTORY_ENTRIES:
                            history.entries = history.entries[-MAX_HISTORY_ENTRIES:]
                        history.save()
                    self._send_json(200, {"status": "ok", "added": added})
                    return

                if self.path == "/clipboard":
                    action = str(data.get("action", ""))
                    if action not in CLIPBOARD_ACTIONS:
                        self._send_json(400, {"error": "gecersiz eylem"})
                        return
                    if action == "push":
                        text = str(data.get("text", ""))
                        if len(text) > CLIPBOARD_MAX_LENGTH:
                            self._send_json(400, {"error": "metin cok uzun"})
                            return
                        if not set_clipboard_text(text):
                            self._send_json(500, {"error": "panoya yazilamadi"})
                            return
                        self._send_json(200, {"status": "ok"})
                        return
                    # action == "pull"
                    self._send_json(200, {"status": "ok", "text": get_clipboard_text()})
                    return

                # self.path == "/alerts"
                try:
                    since_id = int(data.get("since_id", 0))
                except (TypeError, ValueError):
                    since_id = 0
                new_alerts = [dict(a) for a in alerts if a["id"] > since_id]
                self._send_json(200, {"status": "ok", "alerts": new_alerts})

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
    except (ValueError, TypeError, AttributeError):
        return False


def find_release_with_asset(releases, asset_name):
    """[releases] listesinde (GitHub Releases API'sinin dondugu sirayla, en
    yeniden eskiye) taslak/on-surum olmayan ve icinde [asset_name] adinda
    bir dosya olan ilk release'i doner - yoksa None. Bu repoda masaustu ve
    mobil uygulamalarin release'leri ayni listede karistigi icin gerekli
    (bkz. UpdateCheckWorker.run)."""
    for release in releases or []:
        if release.get("draft") or release.get("prerelease"):
            continue
        asset_names = {
            str(asset.get("name", "")) for asset in release.get("assets", []) or []
        }
        if asset_name in asset_names:
            return release
    return None


class UpdateCheckWorker(QThread):
    """
    GitHub Releases API'sinden en son surumu sorar. Henuz hic release
    yayinlanmamissa (404) ya da ag erisimi yoksa sessizce hicbir sey
    yapmaz - bu, mevcut kurulumu bozmayan, tamamen opsiyonel bir kontrol.
    """

    # tag_name, html_url, exe_download_url (bulunamazsa bos), checksum_download_url (bulunamazsa bos)
    update_available = pyqtSignal(str, str, str, str)
    check_finished = pyqtSignal(bool, str)  # basarili mi, hata mesaji (varsa)

    def run(self):
        try:
            import urllib.error
            import urllib.request

            # /releases/latest doner reponun en son yayinlanan release'i -
            # ama bu repo'da masaustu ve mobil uygulamalar release'leri
            # paylasir, bu yuzden "en son" bazen diger uygulamaninki olabilir.
            # Bunun yerine listeyi (en yeniden eskiye) tarayip icinde bizim
            # exe'mizin oldugu ilk release'i buluyoruz.
            url = f"https://api.github.com/repos/{GITHUB_REPO}/releases?per_page=10"
            req = urllib.request.Request(
                url,
                headers={
                    "Accept": "application/vnd.github+json",
                    "User-Agent": "ai-kedi-asistani-update-check",
                },
            )
            with urllib.request.urlopen(req, timeout=UPDATE_CHECK_TIMEOUT_SECONDS) as resp:
                releases = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                self.check_finished.emit(True, "")  # henuz release yayinlanmamis
            else:
                self.check_finished.emit(False, f"HTTP {exc.code}")
            return
        except Exception as exc:
            self.check_finished.emit(False, str(exc))
            return

        data = find_release_with_asset(releases, UPDATE_ASSET_NAME)
        if data is None:
            self.check_finished.emit(True, "")  # bu uygulamaya ait release yok
            return

        tag = str(data.get("tag_name", "")).strip()
        html_url = str(data.get("html_url", "")).strip()
        if tag and is_newer_version(tag, APP_VERSION):
            download_url = ""
            checksum_url = ""
            for asset in data.get("assets", []) or []:
                name = str(asset.get("name", ""))
                asset_url = str(asset.get("browser_download_url", ""))
                if name == UPDATE_ASSET_NAME:
                    download_url = asset_url
                elif name == UPDATE_CHECKSUM_ASSET_NAME:
                    checksum_url = asset_url
            self.update_available.emit(tag, html_url, download_url, checksum_url)
        self.check_finished.emit(True, "")


class UpdateDownloadWorker(QThread):
    """
    Bir GitHub Release'inden yeni surum exe'sini indirir, varsa esliginde
    gelen SHA-256 dosyasiyla dogrular. Yalnizca PyInstaller ile derlenmis
    (frozen) halde anlamlidir - kaynaktan calisirken degistirilecek bir
    exe yoktur.
    """

    progress = pyqtSignal(int)  # 0-100 (toplam boyut bilinmiyorsa hic yayinlanmaz)
    finished_ok = pyqtSignal(str)  # indirilen dosyanin tam yolu
    finished_error = pyqtSignal(str)

    def __init__(self, download_url, checksum_url, parent=None):
        super().__init__(parent)
        self.download_url = download_url
        self.checksum_url = checksum_url

    def run(self):
        import hashlib
        import urllib.request

        target_path = os.path.join(base_dir(), "AI-Kedi-Asistani-new.exe")
        try:
            req = urllib.request.Request(
                self.download_url, headers={"User-Agent": "ai-kedi-asistani-update"}
            )
            digest = hashlib.sha256()
            with urllib.request.urlopen(req, timeout=UPDATE_DOWNLOAD_TIMEOUT_SECONDS) as resp:
                total = int(resp.headers.get("Content-Length", 0))
                downloaded = 0
                with open(target_path, "wb") as f:
                    while True:
                        chunk = resp.read(65536)
                        if not chunk:
                            break
                        f.write(chunk)
                        digest.update(chunk)
                        downloaded += len(chunk)
                        if total:
                            self.progress.emit(int(downloaded * 100 / total))
        except Exception as exc:
            try:
                os.remove(target_path)
            except OSError:
                pass
            self.finished_error.emit(f"Indirme basarisiz: {exc}")
            return

        if self.checksum_url:
            try:
                checksum_req = urllib.request.Request(
                    self.checksum_url, headers={"User-Agent": "ai-kedi-asistani-update"}
                )
                with urllib.request.urlopen(
                    checksum_req, timeout=UPDATE_CHECK_TIMEOUT_SECONDS
                ) as resp:
                    expected = resp.read().decode("utf-8").strip().split()[0].lower()
                if expected != digest.hexdigest().lower():
                    os.remove(target_path)
                    self.finished_error.emit(
                        "Indirilen dosyanin bütünlük dogrulamasi basarisiz oldu "
                        "(SHA-256 uyusmuyor); guvenlik icin silindi."
                    )
                    return
            except Exception as exc:
                try:
                    os.remove(target_path)
                except OSError:
                    pass
                self.finished_error.emit(f"Bütünlük dogrulamasi yapilamadi: {exc}")
                return

        self.finished_ok.emit(target_path)


def apply_update_and_restart(new_exe_path):
    """
    Calisan exe'yi indirilen yeni surumle degistirip yeniden baslatir.
    Windows'ta calisan bir exe kendi uzerine yazilamadigindan, mevcut
    surecin (PID) tam olarak kapanmasini bekleyen kucuk bir .bat betigi
    olusturup arka planda calistirir, sonra uygulamayi kapatir.
    Yalnizca PyInstaller ile derlenmis (frozen) halde calisir.
    """
    if not getattr(sys, "frozen", False):
        return False
    if sys.platform != "win32":
        return False

    current_exe = sys.executable
    pid = os.getpid()
    updater_script = os.path.join(base_dir(), "_ai_kedi_update.bat")
    script = (
        "@echo off\r\n"
        ":wait\r\n"
        f'tasklist /FI "PID eq {pid}" | find "{pid}" >nul\r\n'
        "if not errorlevel 1 (\r\n"
        "    timeout /t 1 /nobreak >nul\r\n"
        "    goto wait\r\n"
        ")\r\n"
        f'move /Y "{new_exe_path}" "{current_exe}" >nul\r\n'
        f'start "" "{current_exe}"\r\n'
        'del "%~f0"\r\n'
    )
    try:
        with open(updater_script, "w", encoding="utf-8") as f:
            f.write(script)
        subprocess.Popen(
            ["cmd", "/c", updater_script],
            creationflags=subprocess.CREATE_NO_WINDOW,
            close_fds=True,
        )
    except OSError:
        return False

    QApplication.instance().quit()
    return True


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

    def __init__(self, character_name, theme_mode="dark"):
        super().__init__()
        self.theme_mode = theme_mode
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setFixedSize(320, 220)
        self._build_ui(character_name)

    def _build_ui(self, character_name):
        palette = THEME_PALETTES.get(self.theme_mode, THEME_PALETTES["dark"])
        container = QWidget(self)
        container.setGeometry(0, 0, self.width(), self.height())
        container.setObjectName("bubble")
        container.setStyleSheet(panel_stylesheet("bubble", self.theme_mode))

        layout = QVBoxLayout(container)
        layout.setContentsMargins(14, 12, 14, 12)

        header = QHBoxLayout()
        title = QPushButton(f"\U0001F431 {character_name}")
        title.setEnabled(False)
        title.setStyleSheet(
            f"background: transparent; color: {palette['text']}; font-weight: bold; "
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
            f"background: transparent; color: {palette['text_muted']}; "
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
    def __init__(self, history: ChatHistoryManager, character_name, theme_mode="dark"):
        super().__init__()
        self.history = history
        self.theme_mode = theme_mode
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
        palette = THEME_PALETTES.get(self.theme_mode, THEME_PALETTES["dark"])
        container = QWidget(self)
        container.setGeometry(0, 0, self.width(), self.height())
        container.setObjectName("historyPanel")
        container.setStyleSheet(panel_stylesheet("historyPanel", self.theme_mode))

        layout = QVBoxLayout(container)
        layout.setContentsMargins(14, 12, 14, 12)

        header = QHBoxLayout()
        title = QPushButton(f"\U0001F553 {character_name} - Sohbet Gecmisi")
        title.setEnabled(False)
        title.setStyleSheet(
            f"background: transparent; color: {palette['text']}; font-weight: bold; "
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

        search_row = QHBoxLayout()
        self.search_box = QLineEdit()
        self.search_box.setPlaceholderText("Gecmiste ara...")
        self.search_box.textChanged.connect(self.refresh)
        search_row.addWidget(self.search_box, 1)
        self.favorites_btn = QPushButton("★")
        self.favorites_btn.setCheckable(True)
        self.favorites_btn.setFixedSize(30, 30)
        self.favorites_btn.setToolTip("Sadece favoriler")
        self.favorites_btn.toggled.connect(self.refresh)
        search_row.addWidget(self.favorites_btn)
        layout.addLayout(search_row)

        self.list_area = QScrollArea()
        self.list_area.setWidgetResizable(True)
        self.list_area.setFrameShape(QFrame.Shape.NoFrame)
        self.list_area.setStyleSheet("background: transparent; border: none;")
        self.list_container = QWidget()
        self.list_container.setStyleSheet("background: transparent;")
        self.list_layout = QVBoxLayout(self.list_container)
        self.list_layout.setContentsMargins(0, 0, 0, 0)
        self.list_layout.addStretch()
        self.list_area.setWidget(self.list_container)
        layout.addWidget(self.list_area, 1)

        footer = QHBoxLayout()
        export_btn = QPushButton("Disa Aktar...")
        export_btn.clicked.connect(self._on_export)
        footer.addWidget(export_btn)
        footer.addStretch()
        clear_btn = QPushButton("Gecmisi Temizle")
        clear_btn.clicked.connect(self._on_clear)
        footer.addWidget(clear_btn)
        layout.addLayout(footer)

    def _visible_entries(self):
        query = self.search_box.text().strip().lower()
        entries = self.history.entries
        if query:
            entries = [
                e
                for e in entries
                if query in str(e.get("question", "")).lower()
                or query in str(e.get("answer", "")).lower()
            ]
        if self.favorites_btn.isChecked():
            entries = [e for e in entries if e.get("favorite")]
        return entries

    def refresh(self):
        while self.list_layout.count() > 1:  # son eleman hep addStretch()
            item = self.list_layout.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.deleteLater()

        if not self.history.entries:
            self.list_layout.insertWidget(0, self._make_message_label("Henuz bir sohbet gecmisi yok."))
            return
        entries = self._visible_entries()
        if not entries:
            self.list_layout.insertWidget(0, self._make_message_label("Eslesen kayit bulunamadi."))
            return
        for i, entry in enumerate(reversed(entries)):  # en yeni en ustte
            row = self._make_entry_row(entry)
            self.list_layout.insertWidget(i, row)

    def _make_message_label(self, text):
        palette = THEME_PALETTES.get(self.theme_mode, THEME_PALETTES["dark"])
        label = QLabel(text)
        label.setStyleSheet(f"color: {palette['text_muted']}; border: none; padding: 8px;")
        return label

    def _make_entry_row(self, entry):
        palette = THEME_PALETTES.get(self.theme_mode, THEME_PALETTES["dark"])
        row = QWidget()
        row_layout = QVBoxLayout(row)
        row_layout.setContentsMargins(4, 6, 4, 6)
        row_layout.setSpacing(2)

        header = QHBoxLayout()
        time_label = QLabel(f"[{entry.get('time', '')}]")
        time_label.setStyleSheet(f"color: {palette['text_muted']}; font-size: 10px; border: none;")
        header.addWidget(time_label)
        header.addStretch()
        star_btn = QPushButton("★" if entry.get("favorite") else "☆")
        star_btn.setFixedSize(22, 20)
        star_btn.setStyleSheet(
            f"background: transparent; border: none; color: {palette['text']}; font-size: 13px; padding: 0;"
        )
        star_btn.clicked.connect(lambda: self._toggle_favorite(entry))
        header.addWidget(star_btn)
        row_layout.addLayout(header)

        q_label = QLabel(f"Sen: {entry.get('question', '')}")
        q_label.setWordWrap(True)
        q_label.setStyleSheet(f"color: {palette['text_muted']}; font-size: 12px; border: none;")
        row_layout.addWidget(q_label)

        marker = "⚠" if entry.get("is_error") else "\U0001F431"
        a_label = QLabel(f"{marker} {entry.get('answer', '')}")
        a_label.setWordWrap(True)
        a_label.setStyleSheet(f"color: {palette['text']}; font-size: 12px; border: none;")
        row_layout.addWidget(a_label)

        return row

    def _toggle_favorite(self, entry):
        entry["favorite"] = not entry.get("favorite", False)
        self.history.save()
        self.refresh()

    def _on_clear(self):
        self.history.clear()
        self.refresh()

    def _on_export(self):
        entries = self._visible_entries()
        if not entries:
            QMessageBox.information(self, "Disa Aktar", "Aktarilacak bir kayit yok.")
            return
        path, _ = QFileDialog.getSaveFileName(
            self, "Sohbet Gecmisini Disa Aktar", "sohbet-gecmisi.txt", "Metin Dosyalari (*.txt)"
        )
        if not path:
            return
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(format_history_entries(entries))
        except OSError as exc:
            QMessageBox.warning(self, "Disa Aktarilamadi", f"Dosya yazilamadi: {exc}")


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

        self.remote_server = RemoteCommandServer(self.config, self.history, self)
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
        self._update_download_worker = None
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
            self.bubble = ChatBubble(
                self.config.get("character_name"), self.config.get("theme_mode")
            )
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
            self.history_dialog = ChatHistoryDialog(
                self.history,
                self.config.get("character_name"),
                self.config.get("theme_mode"),
            )
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
        self.remote_server.add_alert(text)

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

    # -- yedekleme / geri yukleme -------------------------------------------

    def _export_backup(self):
        self._register_activity()
        path, _ = QFileDialog.getSaveFileName(
            self, "Yedek Al", "ai-kedi-asistani-yedek.json", "JSON Dosyalari (*.json)"
        )
        if not path:
            return
        backup = {
            "config": self.config.data,
            "history": self.history.entries,
        }
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(backup, f, ensure_ascii=False, indent=2)
        except OSError as exc:
            QMessageBox.warning(self, "Yedek Alinamadi", f"Yedek kaydedilemedi: {exc}")
            return
        QMessageBox.information(
            self,
            "Yedek Alindi",
            f"Yedek kaydedildi:\n{path}\n\n"
            "Not: Bu dosya Gemini API anahtarinizi ve uzaktan kumanda PIN'inizi "
            "duz metin olarak icerir - baskalariyla paylasmayin.",
        )

    def _import_backup(self):
        self._register_activity()
        path, _ = QFileDialog.getOpenFileName(
            self, "Yedekten Geri Yukle", "", "JSON Dosyalari (*.json)"
        )
        if not path:
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                backup = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            QMessageBox.warning(self, "Geri Yukleme Basarisiz", f"Dosya okunamadi: {exc}")
            return
        if not isinstance(backup, dict):
            QMessageBox.warning(self, "Geri Yukleme Basarisiz", "Gecersiz yedek dosyasi.")
            return

        confirm = QMessageBox.question(
            self,
            "Geri Yukleme Onayi",
            "Mevcut ayarlar ve sohbet gecmisi bu yedekle degistirilecek. Devam edilsin mi?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if confirm != QMessageBox.StandardButton.Yes:
            return

        config_data = backup.get("config")
        if isinstance(config_data, dict):
            self.config.data.update(config_data)
            self.config.save()
        history_data = backup.get("history")
        if isinstance(history_data, list):
            self.history.entries = history_data
            self.history.save()
            if self.history_dialog is not None:
                self.history_dialog.refresh()

        QMessageBox.information(
            self,
            "Geri Yuklendi",
            "Yedek geri yuklendi. Degisikliklerin tam olarak yansimasi icin "
            "uygulamayi yeniden baslatmaniz onerilir.",
        )

    # -- hakkinda -------------------------------------------------------

    def _show_about(self):
        self._register_activity()
        QMessageBox.about(
            self,
            "Hakkinda",
            f"<b>AI Kedi Asistani</b><br>"
            f"Surum {APP_VERSION}<br><br>"
            "Google Gemini destekli, masaustunde gezinen bir kedi asistani.<br><br>"
            f'<a href="https://github.com/{GITHUB_REPO}">GitHub deposu</a>',
        )

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

    def _on_update_available(self, tag, html_url, download_url, checksum_url):
        self._last_update_info = (tag, html_url, download_url, checksum_url)
        if not self._update_check_manual and self.tray_icon is not None:
            self.tray_icon.showMessage(
                "Yeni surum mevcut",
                f"AI Kedi Asistani {tag} yayinlandi. Detaylar icin tiklayin.",
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
            self._offer_update(*self._last_update_info)
        else:
            QMessageBox.information(
                self, "Guncelleme Kontrolu", f"Kullandiginiz surum guncel ({APP_VERSION})."
            )

    def _on_tray_message_clicked(self):
        if self._last_update_info is not None:
            self._offer_update(*self._last_update_info)

    def _offer_update(self, tag, html_url, download_url, checksum_url):
        can_auto_update = getattr(sys, "frozen", False) and sys.platform == "win32" and download_url

        box = QMessageBox(self)
        box.setWindowTitle("Guncelleme Mevcut")
        if can_auto_update:
            box.setText(
                f"Yeni surum mevcut: {tag} (su an: {APP_VERSION})\n\n"
                "Otomatik olarak indirilip kurulsun mu? Uygulama kisa sureligine "
                "kapanip yeniden acilacak."
            )
            download_btn = box.addButton("Simdi Indir ve Kur", QMessageBox.ButtonRole.AcceptRole)
        else:
            box.setText(
                f"Yeni surum mevcut: {tag} (su an: {APP_VERSION})\n\n"
                f"{html_url}\n\n"
                "(Otomatik guncelleme yalnizca derlenmis .exe surumunde "
                "calisir; kaynak koddan calistiriyorsaniz elle indirin.)"
            )
            download_btn = None
        box.addButton("Daha Sonra", QMessageBox.ButtonRole.RejectRole)
        box.exec()
        if download_btn is not None and box.clickedButton() == download_btn:
            self._start_update_download(download_url, checksum_url)

    def _start_update_download(self, download_url, checksum_url):
        progress = QProgressDialog("Guncelleme indiriliyor...", "Iptal", 0, 100, self)
        progress.setWindowTitle("Guncelleniyor")
        progress.setWindowModality(Qt.WindowModality.WindowModal)
        progress.setMinimumDuration(0)
        progress.setAutoClose(False)

        worker = UpdateDownloadWorker(download_url, checksum_url, self)
        self._update_download_worker = worker  # referansi canli tut

        worker.progress.connect(progress.setValue)
        progress.canceled.connect(worker.terminate)

        def on_ok(path):
            progress.close()
            restart_box = QMessageBox(self)
            restart_box.setWindowTitle("Guncelleme Indirildi")
            restart_box.setText(
                "Guncelleme indirildi ve dogrulandi. Simdi yeniden baslatilsin mi?"
            )
            restart_btn = restart_box.addButton("Simdi Yeniden Baslat", QMessageBox.ButtonRole.AcceptRole)
            restart_box.addButton("Daha Sonra", QMessageBox.ButtonRole.RejectRole)
            restart_box.exec()
            if restart_box.clickedButton() == restart_btn:
                if not apply_update_and_restart(path):
                    QMessageBox.warning(
                        self, "Guncelleme", "Guncelleme uygulanamadi; elle indirip kurmayi deneyin."
                    )

        def on_error(message):
            progress.close()
            QMessageBox.warning(self, "Guncelleme", message)

        worker.finished_ok.connect(on_ok)
        worker.finished_error.connect(on_error)
        worker.start()

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
        self.tray_icon.messageClicked.connect(self._on_tray_message_clicked)
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

    def _toggle_theme(self, checked):
        self.config.set("theme_mode", "light" if checked else "dark")
        # Acik konuşma balonu/gecmis panelini kapat - bir sonraki acilista
        # yeni temayla yeniden olusturulacaklar (bkz. _open_bubble/_open_history).
        if self.bubble is not None:
            self.bubble.close()
            self.bubble = None
        if self.history_dialog is not None:
            self.history_dialog.close()
            self.history_dialog = None

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

        light_theme_action = QAction("Acik Tema", self)
        light_theme_action.setCheckable(True)
        light_theme_action.setChecked(self.config.get("theme_mode") == "light")
        light_theme_action.toggled.connect(self._toggle_theme)
        menu.addAction(light_theme_action)

        update_action = QAction("Guncellemeleri Kontrol Et", self)
        update_action.triggered.connect(lambda: self._check_for_updates(manual=True))
        menu.addAction(update_action)

        menu.addSeparator()

        backup_action = QAction("Yedek Al...", self)
        backup_action.triggered.connect(self._export_backup)
        menu.addAction(backup_action)

        restore_action = QAction("Yedekten Geri Yukle...", self)
        restore_action.triggered.connect(self._import_backup)
        menu.addAction(restore_action)

        menu.addSeparator()

        about_action = QAction("Hakkinda", self)
        about_action.triggered.connect(self._show_about)
        menu.addAction(about_action)

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
