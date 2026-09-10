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

import json
import os
import sys
import time

from PyQt6.QtCore import QPoint, Qt, QThread, QTimer, pyqtSignal
from PyQt6.QtGui import (
    QAction,
    QActionGroup,
    QBrush,
    QColor,
    QFont,
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
    QPushButton,
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
ASSETS_DIR = resource_path("assets")

SLEEP_AFTER_MS = 3 * 60 * 1000  # 3 dakika hareketsizlikten sonra uyku
REVERT_TO_NORMAL_MS = 4000  # smile/fear gosterildikten sonra norm'a donus

FALLBACK_MODEL = "gemini-1.5-flash"
OVERLOAD_RETRY_DELAYS = (2, 4)  # saniye; ana modelde 503 aldiginda bekleme sureleri

STATE_FILES = {
    "norm": "fuff_norm.png",
    "zzz": "fuff_zzz.png",
    "smile": "fuff_smile.png",
    "stern": "fuff_stern.png",
    "fear": "fuff_fear.png",
}

DEFAULT_CONFIG = {
    "character_name": "Fuff",
    "gemini_api_key": "",
    "scale_percent": 100,
    "model_name": "gemini-2.0-flash",
    "pos_x": None,
    "pos_y": None,
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
        else:
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


# --------------------------------------------------------------------------
# Gorsel yukleme (assets eksikse basit bir yer tutucu cizilir)
# --------------------------------------------------------------------------

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


def load_pixmap(filename, placeholder_label=""):
    path = os.path.join(ASSETS_DIR, filename)
    if os.path.exists(path):
        pixmap = QPixmap(path)
        if not pixmap.isNull():
            return pixmap
    return make_placeholder_pixmap(label=placeholder_label)


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
                if self._is_overload_error(primary_exc) and self.model_name != FALLBACK_MODEL:
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

        self._position_window()
        self._set_state("norm")

        self.sleep_check_timer = QTimer(self)
        self.sleep_check_timer.timeout.connect(self._check_sleep)
        self.sleep_check_timer.start(5000)

        self.revert_timer = QTimer(self)
        self.revert_timer.setSingleShot(True)
        self.revert_timer.timeout.connect(lambda: self._set_state("norm"))

    # -- gorsel yukleme / olcekleme -------------------------------------

    def _load_pixmaps(self):
        for state, filename in STATE_FILES.items():
            raw = load_pixmap(filename, state)
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

        bubble_x = self.x() + self.width() // 2 - self.bubble.width() // 2
        bubble_y = self.y() - self.bubble.height() - 10

        screen = QApplication.primaryScreen().availableGeometry()
        bubble_x = max(screen.left(), min(bubble_x, screen.right() - self.bubble.width()))
        bubble_y = max(screen.top(), bubble_y)

        self.bubble.move(bubble_x, bubble_y)
        self.bubble.show()
        self.bubble.raise_()
        self.bubble.activateWindow()

    def _handle_question(self, question):
        api_key = self.config.get("gemini_api_key")
        if not api_key:
            self.bubble.show_error("Once sag tik menusunden Gemini API Key ayarini girin.")
            return

        self._register_activity()
        self.revert_timer.stop()
        self._set_state("stern")
        self.bubble.show_thinking()

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

    def _on_answer_error(self, text):
        self._set_state("fear")
        self.revert_timer.start(REVERT_TO_NORMAL_MS)
        if self.bubble:
            self.bubble.show_error(text)

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

        rename_action = QAction("Kediye Isim Ver", self)
        rename_action.triggered.connect(self._rename_character)
        menu.addAction(rename_action)

        api_key_action = QAction("Gemini API Key Ayarlari", self)
        api_key_action.triggered.connect(self._set_api_key)
        menu.addAction(api_key_action)

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

    def _rename_character(self):
        current = self.config.get("character_name")
        name, ok = QInputDialog.getText(self, "Kediye Isim Ver", "Yeni isim:", text=current)
        if ok and name.strip():
            self.config.set("character_name", name.strip())
            self.bubble = None  # yeni isimle yeniden olusturulsun

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
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    config = ConfigManager(CONFIG_PATH)
    cat = CatCharacter(config)
    cat.show()

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
