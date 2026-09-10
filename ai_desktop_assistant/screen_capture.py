"""
screen_capture.py
------------------
mss tabanli, performansli ekran yakalama modulu. Yakalanan goruntuyu
dogrudan bir PIL Image (RGB) nesnesine cevirir; PNG encode/decode
adimina girmeden yapay zeka modeline (orn. Gemini) gonderilmeye
hazir hale gelir.

Kurulum:
    pip install mss pillow

Ornek kullanim en altta yer alir.
"""

from __future__ import annotations

import logging
from typing import Any, Optional

import mss
import mss.exception
from PIL import Image

logger = logging.getLogger(__name__)


def capture_screen(monitor_index: int = 0) -> Optional[Image.Image]:
    """
    Tek seferlik ekran yakalama.

    monitor_index:
        0 -> tum sanal masaustu (coklu monitor dahil, varsayilan)
        1 -> birincil monitor
        2, 3, ... -> diger monitorler (sirayla)

    Basarili olursa RGB modunda bir PIL.Image.Image, hata durumunda
    None doner (istisna disariya firlatilmaz, loglanir).
    """
    try:
        with mss.mss() as sct:
            return _grab_as_image(sct, monitor_index)
    except mss.exception.ScreenShotError as exc:
        logger.error("Ekran yakalama basarisiz: %s", exc)
        return None
    except Exception as exc:  # beklenmeyen platform/surucu hatalari
        logger.error("Beklenmeyen hata (ekran yakalama): %s", exc)
        return None


class ScreenCapturer:
    """
    Ardisik / sik cagrilan yakalamalar icin optimize edilmis siniftir:
    mss oturumunu acik tutar, her cagrida yeniden ac/kapa maliyetine
    girmez ve bellek sizintisi olmadan `with` blogundan cikinca
    kaynaklari serbest birakir.

    Kullanim:
        with ScreenCapturer(monitor_index=1) as capturer:
            image = capturer.capture()
    """

    def __init__(self, monitor_index: int = 0) -> None:
        self.monitor_index = monitor_index
        self._sct: Optional[Any] = None

    def __enter__(self) -> "ScreenCapturer":
        self._sct = mss.mss()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        if self._sct is not None:
            self._sct.close()
            self._sct = None

    def capture(self) -> Optional[Image.Image]:
        if self._sct is None:
            raise RuntimeError(
                "ScreenCapturer yalnizca 'with' blogu icinde kullanilabilir."
            )
        try:
            return _grab_as_image(self._sct, self.monitor_index)
        except mss.exception.ScreenShotError as exc:
            logger.error("Ekran yakalama basarisiz: %s", exc)
            return None
        except Exception as exc:
            logger.error("Beklenmeyen hata (ekran yakalama): %s", exc)
            return None


def _grab_as_image(sct, monitor_index: int) -> Image.Image:
    monitor = sct.monitors[monitor_index]
    shot = sct.grab(monitor)
    # shot.rgb, BGRA->RGB donusumunu mss icinde (C seviyesinde) yapar;
    # PNG'e encode/decode etmeden dogrudan PIL Image uretmek en hizli yol.
    return Image.frombytes("RGB", shot.size, shot.rgb)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    # 1) Tek seferlik kullanim (orn. AI asistaninda soru sorulunca)
    image = capture_screen(monitor_index=0)
    if image is not None:
        print(f"Yakalandi: boyut={image.size}, mod={image.mode}")
        image.save("ekran_ciktisi.png")  # sadece test amacli, opsiyonel

    # 2) Ardisik/tekrarli kullanim (tek mss oturumu ile birden fazla kare)
    with ScreenCapturer(monitor_index=0) as capturer:
        for i in range(3):
            frame = capturer.capture()
            if frame is not None:
                print(f"Kare {i + 1}: {frame.size}")

    # 3) Google Gemini (google-genai) ile birlikte kullanim ornegi:
    #
    #     from google import genai
    #     from screen_capture import capture_screen
    #
    #     image = capture_screen()
    #     if image is not None:
    #         client = genai.Client(api_key="GEMINI_API_KEY")
    #         response = client.models.generate_content(
    #             model="gemini-2.0-flash",
    #             # google-genai SDK'si PIL Image nesnesini contents
    #             # listesinde dogrudan kabul eder, bayta cevirmeye gerek yok.
    #             contents=["Ekranda ne goruyorsun?", image],
    #         )
    #         print(response.text)
