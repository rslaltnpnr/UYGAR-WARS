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
    _parse_version,
    find_release_with_asset,
    is_newer_version,
    is_url_safe_to_open,
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
