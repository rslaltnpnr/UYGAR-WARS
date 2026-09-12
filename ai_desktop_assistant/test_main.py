"""
main.py icindeki saf mantik fonksiyonlari icin testler (surum
karsilastirma, release secimi, SSRF korumasi). GUI/PyQt widget'lari
olusturmaz - main() cagirilmadigi surece QApplication hic acilmaz, bu
yuzden bu testler ekransiz (headless) CI'da da calisir.

Calistirmak icin:
    pip install -r requirements.txt -r requirements-dev.txt
    pytest
"""

from main import (
    HISTORY_ENTRY_MAX_FIELD_LENGTH,
    _parse_version,
    find_release_with_asset,
    is_newer_version,
    is_url_safe_to_open,
    merge_history_entries,
)


class TestParseVersion:
    def test_basit_surum(self):
        assert _parse_version("v1.2.3") == (1, 2, 3)

    def test_v_onekisiz(self):
        assert _parse_version("1.2.3") == (1, 2, 3)

    def test_eksik_parca_sifir_sayilir(self):
        assert _parse_version("v1.2") == (1, 2)

    def test_sayisal_olmayan_parca_sifir_sayilir(self):
        assert _parse_version("vabc.2.3") == (0, 2, 3)


class TestIsNewerVersion:
    def test_daha_yuksek_patch_daha_yeni(self):
        assert is_newer_version("v1.1.1", "1.1.0") is True

    def test_daha_yuksek_minor_daha_yeni(self):
        assert is_newer_version("v1.2.0", "1.1.9") is True

    def test_ayni_surum_daha_yeni_degil(self):
        assert is_newer_version("v1.1.1", "1.1.1") is False

    def test_daha_eski_surum_daha_yeni_degil(self):
        assert is_newer_version("v1.0.0", "1.1.0") is False

    def test_cift_haneli_parcalar_sozluksel_degil(self):
        assert is_newer_version("v1.10.0", "1.9.0") is True

    def test_gecersiz_girdi_false_doner(self):
        assert is_newer_version(None, "1.0.0") is False


class TestFindReleaseWithAsset:
    def test_depo_release_listesini_masaustu_ve_mobil_karisikken_dogru_ayiklar(self):
        # Gercek senaryo: mobil daha yeni bir release yayinladi (sadece
        # .apk), masaustunun kendi surumu listede daha asagida. Ham
        # /releases/latest kullansaydik yanlislikla mobil release'ini
        # bulurduk.
        releases = [
            {
                "tag_name": "v1.0.1",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "ai-kedi-asistani.apk"}],
            },
            {
                "tag_name": "v1.2.1",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "AI-Kedi-Asistani.exe"}],
            },
        ]
        found = find_release_with_asset(releases, "AI-Kedi-Asistani.exe")
        assert found is not None
        assert found["tag_name"] == "v1.2.1"

    def test_taslak_release_atlanir(self):
        releases = [
            {
                "tag_name": "v2.0.0",
                "draft": True,
                "prerelease": False,
                "assets": [{"name": "AI-Kedi-Asistani.exe"}],
            },
            {
                "tag_name": "v1.0.0",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "AI-Kedi-Asistani.exe"}],
            },
        ]
        found = find_release_with_asset(releases, "AI-Kedi-Asistani.exe")
        assert found["tag_name"] == "v1.0.0"

    def test_on_surum_atlanir(self):
        releases = [
            {
                "tag_name": "v2.0.0-beta",
                "draft": False,
                "prerelease": True,
                "assets": [{"name": "AI-Kedi-Asistani.exe"}],
            },
            {
                "tag_name": "v1.0.0",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "AI-Kedi-Asistani.exe"}],
            },
        ]
        found = find_release_with_asset(releases, "AI-Kedi-Asistani.exe")
        assert found["tag_name"] == "v1.0.0"

    def test_eslesen_asset_yoksa_none_doner(self):
        releases = [
            {
                "tag_name": "v1.0.1",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "ai-kedi-asistani.apk"}],
            }
        ]
        assert find_release_with_asset(releases, "AI-Kedi-Asistani.exe") is None

    def test_bos_liste_none_doner(self):
        assert find_release_with_asset([], "AI-Kedi-Asistani.exe") is None


class TestIsUrlSafeToOpen:
    """IP literalleriyle test edilir - getaddrinfo bunlari gercek bir DNS
    sorgusu yapmadan yerel olarak cozer, bu yuzden testler ag erisimi
    gerektirmez ve CI'da guvenilir sekilde calisir."""

    def test_genel_ip_izinli(self):
        assert is_url_safe_to_open("http://8.8.8.8/x") is True

    def test_loopback_reddedilir(self):
        assert is_url_safe_to_open("http://127.0.0.1/x") is False

    def test_ozel_ag_reddedilir(self):
        assert is_url_safe_to_open("http://192.168.1.1/x") is False
        assert is_url_safe_to_open("http://10.0.0.1/x") is False
        assert is_url_safe_to_open("http://172.16.0.1/x") is False

    def test_link_local_reddedilir(self):
        assert is_url_safe_to_open("http://169.254.1.1/x") is False

    def test_localhost_hostname_reddedilir(self):
        assert is_url_safe_to_open("http://localhost/x") is False

    def test_gecersiz_sema_reddedilir(self):
        assert is_url_safe_to_open("ftp://8.8.8.8/x") is False
        assert is_url_safe_to_open("file:///etc/passwd") is False

    def test_cozulemeyen_host_reddedilir(self):
        assert is_url_safe_to_open("http://bu-host-kesinlikle-yok.invalid/x") is False


class TestMergeHistoryEntries:
    def test_yeni_kayitlar_eklenir(self):
        existing = [
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1", "is_error": False}
        ]
        new = [
            {"time": "2026-01-01 11:00", "question": "q2", "answer": "a2", "is_error": False}
        ]
        added = merge_history_entries(existing, new)
        assert added == 1
        assert len(existing) == 2
        assert existing[1]["question"] == "q2"

    def test_ayni_zaman_soru_cevap_uclusu_tekrar_eklenmez(self):
        existing = [
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1", "is_error": False}
        ]
        new = [
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1", "is_error": False}
        ]
        added = merge_history_entries(existing, new)
        assert added == 0
        assert len(existing) == 1

    def test_ayni_liste_icindeki_tekrarlar_da_bir_kez_eklenir(self):
        existing = []
        new = [
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1"},
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1"},
        ]
        added = merge_history_entries(existing, new)
        assert added == 1
        assert len(existing) == 1

    def test_zaman_veya_soru_bos_kayit_atlanir(self):
        existing = []
        new = [
            {"time": "", "question": "q1", "answer": "a1"},
            {"time": "2026-01-01 10:00", "question": "", "answer": "a1"},
        ]
        added = merge_history_entries(existing, new)
        assert added == 0
        assert existing == []

    def test_dict_olmayan_kayit_atlanir(self):
        existing = []
        added = merge_history_entries(existing, ["gecersiz", 42, None])
        assert added == 0
        assert existing == []

    def test_alanlar_maksimum_uzunluga_kesilir(self):
        existing = []
        long_text = "x" * (HISTORY_ENTRY_MAX_FIELD_LENGTH + 100)
        new = [{"time": "2026-01-01 10:00", "question": long_text, "answer": long_text}]
        merge_history_entries(existing, new)
        assert len(existing[0]["question"]) == HISTORY_ENTRY_MAX_FIELD_LENGTH
        assert len(existing[0]["answer"]) == HISTORY_ENTRY_MAX_FIELD_LENGTH

    def test_eksik_is_error_false_varsayilir(self):
        existing = []
        new = [{"time": "2026-01-01 10:00", "question": "q1", "answer": "a1"}]
        merge_history_entries(existing, new)
        assert existing[0]["is_error"] is False
